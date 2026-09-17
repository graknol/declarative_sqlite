import { describe, it, expect } from 'vitest';
import { diffSchema } from './diff';
import type { Schema, TableDef } from '../schema/types';

const table = (name: string, columns: TableDef['columns'], keys: TableDef['keys'] = []): TableDef => ({ name, columns, keys, library: false });
const text = (name: string) => ({ name, type: 'TEXT' as const, logical: 'text' as const, notNull: false });
const real = (name: string) => ({ name, type: 'REAL' as const, logical: 'real' as const, notNull: false });
const schema = (...tables: TableDef[]): Schema => ({ tables });

describe('diffSchema', () => {
  it('reports no changes for identical schemas', () => {
    const s = schema(table('t', [text('a')]));
    expect(diffSchema(s, s).hasChanges).toBe(false);
  });

  it('creates a declared table the database does not have', () => {
    const diff = diffSchema(schema(table('t', [text('a')])), schema());
    expect(diff.tablesToCreate.map((t) => t.name)).toEqual(['t']);
    expect(diff.hasChanges).toBe(true);
  });

  it('adds a declared column the table is missing', () => {
    const diff = diffSchema(schema(table('t', [text('a'), text('b')])), schema(table('t', [text('a')])));
    expect(diff.tablesToAlter[0]?.columnsToAdd.map((c) => c.name)).toEqual(['b']);
    expect(diff.tablesToAlter[0]?.requiresRecreate).toBe(false);
  });

  it('adds a declared index the table is missing', () => {
    const declared = schema(table('t', [text('a')], [{ columns: ['a'], type: 'INDEX', name: 'idx_t_a' }]));
    const diff = diffSchema(declared, schema(table('t', [text('a')])));
    expect(diff.tablesToAlter[0]?.keysToAdd).toEqual([{ columns: ['a'], type: 'INDEX', name: 'idx_t_a' }]);
  });

  it('never drops a table or column the database has and the schema does not', () => {
    const diff = diffSchema(schema(table('t', [text('a')])), schema(table('t', [text('a'), text('legacy')]), table('old', [text('x')])));
    expect(diff.extraTables).toEqual(['old']);
    expect(diff.extraColumns).toEqual([{ table: 't', column: 'legacy' }]);
    expect(diff.tablesToAlter).toEqual([]);
    expect(diff.hasChanges).toBe(false);
  });

  it('requires a recreate when a storage type changed', () => {
    const diff = diffSchema(schema(table('t', [real('a')])), schema(table('t', [text('a')])));
    const alteration = diff.tablesToAlter[0];
    expect(alteration?.requiresRecreate).toBe(true);
    expect(alteration?.columnsToRetype).toEqual([
      { from: { name: 'a', type: 'TEXT', logical: 'text', notNull: false }, to: { name: 'a', type: 'REAL', logical: 'real', notNull: false } },
    ]);
  });

  it('does not require a recreate when only the logical type differs', () => {
    const declared = schema(table('t', [{ name: 'd', type: 'TEXT', logical: 'date', notNull: false }]));
    const live = schema(table('t', [text('d')]));
    expect(diffSchema(declared, live).hasChanges).toBe(false);
  });

  it('requires a recreate when the declared primary key differs', () => {
    const declared = schema(table('t', [text('a')], [{ columns: ['a'], type: 'PRIMARY' }]));
    const live = schema(table('t', [text('a')]));
    expect(diffSchema(declared, live).tablesToAlter[0]?.requiresRecreate).toBe(true);
  });
});
