import { describe, it, expect } from 'vitest';
import { SchemaBuilder } from './schema-builder';

function appSchema() {
  const schema = new SchemaBuilder();
  schema.table('c_work_task', (t) => {
    t.text('system_id');
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate').maxLength(100);
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  schema.table('local_prefs', (t) => {
    t.text('key').notNull('');
    t.text('value');
  });
  return schema.build();
}

describe('SchemaBuilder', () => {
  it('builds the declared tables and appends the library tables', () => {
    const schema = appSchema();
    expect(schema.tables.map((t) => t.name)).toEqual(['c_work_task', 'local_prefs', 'outbox', 'sync_cursor']);
  });

  it('marks the library tables as library and never as synced', () => {
    const outbox = appSchema().tables.find((t) => t.name === 'outbox');
    expect(outbox?.library).toBe(true);
    expect(outbox?.synced).toBeUndefined();
  });

  it('carries the synced declaration through to the table', () => {
    const task = appSchema().tables.find((t) => t.name === 'c_work_task');
    expect(task?.synced).toEqual({ key: 'system_id', scope: ['wo_no'] });
  });

  it('refuses a table named like a library table', () => {
    const schema = new SchemaBuilder();
    expect(() => schema.table('outbox', (t) => t.text('id'))).toThrow(/outbox/);
  });

  it('refuses the same table declared twice', () => {
    const schema = new SchemaBuilder();
    schema.table('c_ncr', (t) => t.text('ncr_no'));
    expect(() => schema.table('c_ncr', (t) => t.text('ncr_no'))).toThrow(/c_ncr/);
  });
});
