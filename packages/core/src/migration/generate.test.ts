import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { generateMigration, createTableSql, MigrationBlockedError } from './generate';
import { diffSchema } from './diff';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { TableBuilder } from '../schema/table-builder';
import type { Schema, TableDef } from '../schema/types';

const table = (name: string, columns: TableDef['columns'], keys: TableDef['keys'] = []): TableDef => ({ name, columns, keys, library: false });
const text = (name: string, notNull = false, defaultValue?: string) => ({
  name, type: 'TEXT' as const, logical: 'text' as const, notNull, ...(defaultValue === undefined ? {} : { defaultValue }),
});
const real = (name: string) => ({ name, type: 'REAL' as const, logical: 'real' as const, notNull: false });
const schema = (...tables: TableDef[]): Schema => ({ tables });

describe('generateMigration', () => {
  it('generates CREATE TABLE with the primary key inline', () => {
    const declared = schema(table('t', [text('id', true, ''), real('qty')], [{ columns: ['id'], type: 'PRIMARY' }]));
    const ops = generateMigration(diffSchema(declared, schema()), declared, { allowRecreate: false });
    expect(ops[0]?.sql[0]).toBe(
      'CREATE TABLE "t" (\n  "id" TEXT NOT NULL DEFAULT \'\',\n  "qty" REAL,\n  PRIMARY KEY ("id")\n)',
    );
  });

  it('generates ADD COLUMN with the default so existing rows stay valid', () => {
    const declared = schema(table('t', [text('a'), text('b', true, 'x')]));
    const ops = generateMigration(diffSchema(declared, schema(table('t', [text('a')]))), declared, { allowRecreate: false });
    expect(ops[0]?.sql).toEqual(['ALTER TABLE "t" ADD COLUMN "b" TEXT NOT NULL DEFAULT \'x\'']);
  });

  it('generates CREATE INDEX IF NOT EXISTS', () => {
    const declared = schema(table('t', [text('a')], [{ columns: ['a'], type: 'INDEX', name: 'idx_t_a' }]));
    const ops = generateMigration(diffSchema(declared, schema(table('t', [text('a')]))), declared, { allowRecreate: false });
    expect(ops[0]?.sql).toEqual(['CREATE INDEX IF NOT EXISTS "idx_t_a" ON "t" ("a")']);
  });

  it('refuses a recreate unless it is allowed, naming the table', () => {
    const declared = schema(table('t', [real('a')]));
    const diff = diffSchema(declared, schema(table('t', [text('a')])));
    expect(() => generateMigration(diff, declared, { allowRecreate: false })).toThrow(MigrationBlockedError);
    try {
      generateMigration(diff, declared, { allowRecreate: false });
    } catch (error) {
      expect((error as MigrationBlockedError).tables).toEqual(['t']);
    }
  });

  it('recreates via a temp table copying the columns both schemas share, and carries a column the schema no longer declares instead of dropping it', () => {
    const declared = schema(table('t', [real('a'), text('b')]));
    const diff = diffSchema(declared, schema(table('t', [text('a'), text('gone')])));
    const ops = generateMigration(diff, declared, { allowRecreate: true });
    expect(ops[0]?.sql).toEqual([
      // "b" is newly added by the declared schema (temp table gets it, but with
      // nothing to copy from). "gone" is not declared at all but exists live —
      // it rides along in both the temp table and the INSERT, unlike "b".
      'CREATE TABLE "t__migrate_new" (\n  "a" REAL,\n  "b" TEXT,\n  "gone" TEXT\n)',
      'INSERT INTO "t__migrate_new" ("a", "gone") SELECT "a", "gone" FROM "t"',
      'DROP TABLE "t"',
      'ALTER TABLE "t__migrate_new" RENAME TO "t"',
    ]);
  });

  it('does not emit an empty INSERT when nothing at all overlaps between the old and new shape', () => {
    // Contrived on purpose: a live table with zero columns is not something
    // introspect() would ever produce, but it is the only way to reach the
    // "carried" list being empty now that extraColumns are carried through
    // (fix 1 makes the realistic case — a fully renamed single-column primary
    // key — carry the old column as an extra column instead). The guard exists
    // for this edge regardless of how hard it is to reach.
    const declared = schema(table('t', [text('onlycol', true, 'x')], [{ columns: ['onlycol'], type: 'PRIMARY' }]));
    const live = schema(table('t', [], [{ columns: [], type: 'PRIMARY' }]));
    const ops = generateMigration(diffSchema(declared, live), declared, { allowRecreate: true });
    expect(ops[0]?.sql).toEqual([
      'CREATE TABLE "t__migrate_new" (\n  "onlycol" TEXT NOT NULL DEFAULT \'x\',\n  PRIMARY KEY ("onlycol")\n)',
      'DROP TABLE "t"',
      'ALTER TABLE "t__migrate_new" RENAME TO "t"',
    ]);
  });

  it('refuses to recreate a table with a live extra column that is NOT NULL and has no reconstructable default', () => {
    // parseDefault() in introspect.ts gives up (returns undefined) on a
    // non-literal SQL default such as an expression; simulate that outcome
    // directly rather than depending on introspect's parsing here.
    const declared = schema(table('t', [real('a')]));
    const liveExtra = { name: 'weird', type: 'INTEGER' as const, logical: 'integer' as const, notNull: true };
    const live: Schema = { tables: [{ name: 't', columns: [text('a'), liveExtra], keys: [], library: false }] };
    const diff = diffSchema(declared, live);
    expect(() => generateMigration(diff, declared, { allowRecreate: true })).toThrow(MigrationBlockedError);
    try {
      generateMigration(diff, declared, { allowRecreate: true });
    } catch (error) {
      expect((error as MigrationBlockedError).tables).toEqual(['t']);
      expect((error as Error).message).toContain('weird');
    }
  });

  it('emits CREATE UNIQUE INDEX when the key being added is a UNIQUE constraint, not a plain INDEX', () => {
    // The kind must come from key.type, never from the generated name, so a
    // UNIQUE key added to an existing table is actually enforced as unique.
    const declared = schema(table('t', [text('a')], [{ columns: ['a'], type: 'UNIQUE', name: 'uq_t_a' }]));
    const ops = generateMigration(diffSchema(declared, schema(table('t', [text('a')]))), declared, { allowRecreate: false });
    expect(ops[0]?.sql).toEqual(['CREATE UNIQUE INDEX IF NOT EXISTS "uq_t_a" ON "t" ("a")']);
  });

  describe('executed against a real database', () => {
    let adapter: MemoryAdapter;

    beforeEach(async () => {
      adapter = new MemoryAdapter();
      await adapter.open();
    });

    afterEach(async () => {
      await adapter.close();
    });

    it('runs the CREATE TABLE and ADD COLUMN statements, quoted identifiers included', async () => {
      // A column name with an embedded quote and a space, to prove
      // quoteIdentifier's escaping actually survives execution.
      const weirdColumn = 'na"me with spaces';
      const v1 = schema(table('t', [text('id', true, ''), text(weirdColumn, false)]));
      for (const op of createTableSql(v1.tables[0] as TableDef)) {
        await adapter.exec(op);
      }
      await adapter.run(`INSERT INTO "t" (id) VALUES (?)`, ['row1']);

      const v2 = schema(table('t', [text('id', true, ''), text(weirdColumn, false), text('b', true, 'x')]));
      const ops = generateMigration(diffSchema(v2, v1), v2, { allowRecreate: false });
      for (const op of ops) {
        for (const stmt of op.sql) await adapter.exec(stmt);
      }

      const row = await adapter.get<{ id: string; b: string }>('SELECT id, b FROM "t" WHERE id = ?', ['row1']);
      // The NOT NULL default must have populated the pre-existing row.
      expect(row).toEqual({ id: 'row1', b: 'x' });
    });

    it('enforces a UNIQUE index added to an existing table', async () => {
      const v1 = schema(table('t', [text('a')]));
      for (const op of createTableSql(v1.tables[0] as TableDef)) await adapter.exec(op);
      await adapter.run('INSERT INTO "t" (a) VALUES (?)', ['dup']);

      const v2 = schema(table('t', [text('a')], [{ columns: ['a'], type: 'UNIQUE', name: 'uq_t_a' }]));
      const ops = generateMigration(diffSchema(v2, v1), v2, { allowRecreate: false });
      for (const op of ops) for (const stmt of op.sql) await adapter.exec(stmt);

      await expect(adapter.run('INSERT INTO "t" (a) VALUES (?)', ['dup'])).rejects.toThrow();
    });

    it('runs the recreate flow against a populated table, dropping the column that changed type', async () => {
      const v1 = schema(table('t', [real('a'), text('b')]));
      for (const op of createTableSql(v1.tables[0] as TableDef)) await adapter.exec(op);
      await adapter.run('INSERT INTO "t" (a, b) VALUES (?, ?)', [1.5, 'kept']);

      const declared = schema(table('t', [text('a'), text('b')]));
      const diff = diffSchema(declared, v1);
      const ops = generateMigration(diff, declared, { allowRecreate: true });
      for (const op of ops) for (const stmt of op.sql) await adapter.exec(stmt);

      const row = await adapter.get<{ a: string; b: string }>('SELECT a, b FROM "t"');
      // "a" was copied and converted by SQLite's type affinity, "b" untouched.
      expect(row).toEqual({ a: '1.5', b: 'kept' });
    });

    it('keeps a live-only column and its data through a recreate forced by an unrelated column', async () => {
      const v1 = schema(table('t', [real('a'), text('gone')]));
      for (const op of createTableSql(v1.tables[0] as TableDef)) await adapter.exec(op);
      await adapter.run('INSERT INTO "t" (a, gone) VALUES (?, ?)', [1.5, 'keep-me']);

      // "a" retypes REAL -> TEXT, forcing the recreate; "gone" is not declared
      // by this schema at all.
      const declared = schema(table('t', [text('a')]));
      const diff = diffSchema(declared, v1);
      const ops = generateMigration(diff, declared, { allowRecreate: true });
      for (const op of ops) for (const stmt of op.sql) await adapter.exec(stmt);

      const row = await adapter.get<{ a: string; gone: string }>('SELECT a, gone FROM "t"');
      expect(row).toEqual({ a: '1.5', gone: 'keep-me' });
    });

    it('recreates a column flipped from nullable to NOT NULL, backfilling existing NULLs, and refuses without allowRecreate', async () => {
      const v1 = schema(table('t', [text('id', true, ''), text('a')]));
      for (const op of createTableSql(v1.tables[0] as TableDef)) await adapter.exec(op);
      await adapter.run('INSERT INTO "t" (id, a) VALUES (?, ?)', ['row1', null]);
      await adapter.run('INSERT INTO "t" (id, a) VALUES (?, ?)', ['row2', 'kept']);

      const v2 = schema(table('t', [text('id', true, ''), text('a', true, 'x')]));
      const diff = diffSchema(v2, v1);
      expect(diff.tablesToAlter[0]?.requiresRecreate).toBe(true);
      expect(() => generateMigration(diff, v2, { allowRecreate: false })).toThrow(MigrationBlockedError);

      const ops = generateMigration(diff, v2, { allowRecreate: true });
      for (const op of ops) for (const stmt of op.sql) await adapter.exec(stmt);

      const rows = await adapter.all<{ id: string; a: string }>('SELECT id, a FROM "t" ORDER BY id');
      expect(rows).toEqual([
        { id: 'row1', a: 'x' },
        { id: 'row2', a: 'kept' },
      ]);

      await expect(adapter.run('INSERT INTO "t" (id, a) VALUES (?, ?)', ['row3', null])).rejects.toThrow();
    });

    it('drops and recreates a live key that shares a declared key\'s name but not its shape, so the declared constraint is actually enforced', async () => {
      const v1 = schema(table('t', [text('a')], [{ columns: ['a'], type: 'INDEX', name: 'k_a' }]));
      for (const op of createTableSql(v1.tables[0] as TableDef)) await adapter.exec(op);
      await adapter.run('INSERT INTO "t" (a) VALUES (?)', ['dup']);

      // Same name "k_a", but the declared key is UNIQUE where the live one is a plain INDEX.
      const v2 = schema(table('t', [text('a')], [{ columns: ['a'], type: 'UNIQUE', name: 'k_a' }]));
      const ops = generateMigration(diffSchema(v2, v1), v2, { allowRecreate: false });
      for (const op of ops) for (const stmt of op.sql) await adapter.exec(stmt);

      await expect(adapter.run('INSERT INTO "t" (a) VALUES (?)', ['dup'])).rejects.toThrow();
    });

    it('creates a NOT NULL blob column with an X\'...\' default and reads the default value back', async () => {
      const builder = new TableBuilder('t');
      builder.markLibrary();
      builder.blob('payload').notNull(new Uint8Array([1, 255]));
      const declaredTable = builder.build();

      const sql = createTableSql(declaredTable);
      expect(sql[0]).toContain(`DEFAULT X'01FF'`);
      for (const stmt of sql) await adapter.exec(stmt);
      await adapter.exec('INSERT INTO "t" DEFAULT VALUES');

      const row = await adapter.get<{ payload: Uint8Array }>('SELECT payload FROM "t"');
      expect(row?.payload).toEqual(new Uint8Array([1, 255]));
    });

    it('adds a NOT NULL blob column with an X\'...\' default to a populated table', async () => {
      const v1Builder = new TableBuilder('t');
      v1Builder.markLibrary();
      v1Builder.text('name');
      const v1Table = v1Builder.build();
      for (const stmt of createTableSql(v1Table)) await adapter.exec(stmt);
      await adapter.run('INSERT INTO "t" (name) VALUES (?)', ['row1']);

      const v2Builder = new TableBuilder('t');
      v2Builder.markLibrary();
      v2Builder.text('name');
      v2Builder.blob('payload').notNull(new Uint8Array([1, 255]));
      const v2Table = v2Builder.build();

      const diff = diffSchema(schema(v2Table), schema(v1Table));
      const ops = generateMigration(diff, schema(v2Table), { allowRecreate: false });
      expect(ops[0]?.sql).toEqual([`ALTER TABLE "t" ADD COLUMN "payload" BLOB NOT NULL DEFAULT X'01FF'`]);
      for (const op of ops) for (const stmt of op.sql) await adapter.exec(stmt);

      const row = await adapter.get<{ name: string; payload: Uint8Array }>('SELECT name, payload FROM "t"');
      expect(row?.name).toBe('row1');
      expect(row?.payload).toEqual(new Uint8Array([1, 255]));
    });
  });
});
