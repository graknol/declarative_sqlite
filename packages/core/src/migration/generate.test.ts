import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { generateMigration, createTableSql, MigrationBlockedError } from './generate';
import { diffSchema } from './diff';
import { MemoryAdapter } from '../adapters/memory-adapter';
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

  it('recreates via a temp table copying the columns both schemas share', () => {
    const declared = schema(table('t', [real('a'), text('b')]));
    const diff = diffSchema(declared, schema(table('t', [text('a'), text('gone')])));
    const ops = generateMigration(diff, declared, { allowRecreate: true });
    expect(ops[0]?.sql).toEqual([
      'CREATE TABLE "t__migrate_new" (\n  "a" REAL,\n  "b" TEXT\n)',
      'INSERT INTO "t__migrate_new" ("a") SELECT "a" FROM "t"',
      'DROP TABLE "t"',
      'ALTER TABLE "t__migrate_new" RENAME TO "t"',
    ]);
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
  });
});
