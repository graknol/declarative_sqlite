import { describe, it, expect } from 'vitest';
import { TableBuilder } from './table-builder';

describe('TableBuilder', () => {
  it('adds the system columns the app did not declare', () => {
    const t = new TableBuilder('c_work_order');
    t.text('description').maxLength(200);
    const table = t.build();
    const names = table.columns.map((c) => c.name);
    expect(names).toEqual(['system_id', 'system_removed', 'description']);
    expect(table.columns[0]).toMatchObject({ name: 'system_id', type: 'TEXT', notNull: true, defaultValue: '' });
    expect(table.columns[1]).toMatchObject({ name: 'system_removed', type: 'INTEGER', notNull: true, defaultValue: 0 });
  });

  it('does not duplicate a system column the app declared itself', () => {
    const t = new TableBuilder('c_work_task');
    t.integer('system_removed').notNull(0);
    t.text('action_taken');
    const table = t.build();
    expect(table.columns.filter((c) => c.name === 'system_removed')).toHaveLength(1);
  });

  it('adds sync_seq and a primary key on the sync key for a synced table', () => {
    const t = new TableBuilder('c_work_task');
    t.real('wo_no');
    t.markSynced({ key: 'system_id', scope: ['wo_no'] });
    const table = t.build();
    expect(table.columns.map((c) => c.name)).toContain('sync_seq');
    expect(table.keys).toEqual([{ columns: ['system_id'], type: 'PRIMARY' }]);
    expect(table.synced).toEqual({ key: 'system_id', scope: ['wo_no'] });
  });

  it('keeps the primary key the app declared instead of adding one', () => {
    const t = new TableBuilder('c_work_task');
    t.key('system_id').primary();
    const table = t.build();
    expect(table.keys.filter((k) => k.type === 'PRIMARY')).toHaveLength(1);
  });

  it('names an index when the caller did not', () => {
    const t = new TableBuilder('outbox');
    t.text('status');
    t.text('changed_at');
    t.key('status', 'changed_at').index();
    expect(t.build().keys).toContainEqual({ columns: ['status', 'changed_at'], type: 'INDEX', name: 'idx_outbox_status_changed_at' });
  });

  it('rejects a scope column the table does not declare', () => {
    const t = new TableBuilder('c_work_task');
    t.markSynced({ key: 'system_id', scope: ['wo_no'] });
    expect(() => t.build()).toThrow(/c_work_task.*wo_no/);
  });

  it('rejects a duplicate column name', () => {
    const t = new TableBuilder('c_ncr');
    t.text('notes');
    expect(() => t.text('notes')).toThrow(/notes/);
  });
  it('does not duplicate system_id or sync_seq when the app declares them', () => {
    const t = new TableBuilder('c_work_task');
    t.text('system_id');
    t.integer('sync_seq');
    t.integer('wo_no');
    t.markSynced({ key: 'system_id', scope: ['wo_no'] });
    const names = t.build().columns.map((c) => c.name);
    expect(names.filter((n) => n === 'system_id')).toHaveLength(1);
    expect(names.filter((n) => n === 'sync_seq')).toHaveLength(1);
  });
});