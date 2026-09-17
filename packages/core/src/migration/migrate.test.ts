import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { introspect } from './introspect';
import { MigrationBlockedError } from './generate';
import { planMigration, runMigration } from './migrate';
import type { Schema } from '../schema/types';

function schemaWith(build: (s: SchemaBuilder) => void): Schema {
  const s = new SchemaBuilder();
  build(s);
  return s.build();
}

const v1 = schemaWith((s) => {
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
});

const v2 = schemaWith((s) => {
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.text('rowstate');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('c_ncr', (t) => {
    t.text('ncr_no');
  }).synced({ key: 'system_id', scope: ['ncr_no'] });
});

describe('runMigration', () => {
  let adapter: MemoryAdapter;

  beforeEach(async () => {
    adapter = new MemoryAdapter();
    await adapter.open();
  });

  afterEach(async () => {
    await adapter.close();
  });

  it('creates every declared table including the library tables', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    const live = await introspect(adapter);
    expect(live.tables.map((t) => t.name).sort()).toEqual(['c_work_task', 'outbox', 'sync_cursor']);
  });

  it('is a no-op the second time', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    const second = await runMigration(adapter, v1, { mode: 'auto' });
    expect(second.hasOperations).toBe(false);
    expect(second.applied).toBe(false);
  });

  it('adds a new column and a new table without touching data', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    await adapter.run(`INSERT INTO "c_work_task" ("system_id", "wo_no", "rowstate") VALUES (?, ?, ?)`, ['A', 3188, 'RELEASED']);

    await runMigration(adapter, v2, { mode: 'auto' });

    const row = await adapter.get<{ system_id: string; c_qty_installed: number | null }>(`SELECT * FROM "c_work_task"`);
    expect(row?.system_id).toBe('A');
    expect(row?.c_qty_installed).toBeNull();
    expect((await introspect(adapter)).tables.map((t) => t.name)).toContain('c_ncr');
  });

  it('plan mode reports the operations and executes nothing', async () => {
    const plan = await runMigration(adapter, v1, { mode: 'plan' });
    expect(plan.hasOperations).toBe(true);
    expect(plan.applied).toBe(false);
    expect(plan.operations.map((o) => o.description)).toContain('Create table c_work_task');
    expect((await introspect(adapter)).tables).toEqual([]);
  });

  it('off mode does nothing at all', async () => {
    const plan = await runMigration(adapter, v1, { mode: 'off' });
    expect(plan.operations).toEqual([]);
    expect((await introspect(adapter)).tables).toEqual([]);
  });

  it('refuses a type change without allowRecreate', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    const retyped = schemaWith((s) => {
      s.table('c_work_task', (t) => {
        t.text('wo_no');
        t.text('rowstate');
      }).synced({ key: 'system_id', scope: ['wo_no'] });
    });
    await expect(runMigration(adapter, retyped, { mode: 'auto' })).rejects.toThrow(MigrationBlockedError);
  });

  it('recreates and preserves data with allowRecreate', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    await adapter.run(`INSERT INTO "c_work_task" ("system_id", "wo_no", "rowstate") VALUES (?, ?, ?)`, ['A', 3188, 'RELEASED']);
    const retyped = schemaWith((s) => {
      s.table('c_work_task', (t) => {
        t.text('wo_no');
        t.text('rowstate');
      }).synced({ key: 'system_id', scope: ['wo_no'] });
    });

    await runMigration(adapter, retyped, { mode: 'auto', allowRecreate: true });

    const row = await adapter.get<{ system_id: string; wo_no: string }>(`SELECT * FROM "c_work_task"`);
    // SQLite's REAL->TEXT affinity conversion renders a whole-number real with a
    // trailing ".0" (sqlite3VdbeMemStringify), so the recreated column holds
    // '3188.0', not '3188'. Confirmed against the real sqlite3 WASM build.
    expect(row).toMatchObject({ system_id: 'A', wo_no: '3188.0' });
    const column = (await introspect(adapter)).tables.find((t) => t.name === 'c_work_task')?.columns.find((c) => c.name === 'wo_no');
    expect(column?.type).toBe('TEXT');
  });

  it('leaves a table the schema no longer declares in place', async () => {
    await runMigration(adapter, v2, { mode: 'auto' });
    await runMigration(adapter, v1, { mode: 'auto' });
    expect((await introspect(adapter)).tables.map((t) => t.name)).toContain('c_ncr');
  });

  it('rolls the whole migration back when one statement fails', async () => {
    await runMigration(adapter, v1, { mode: 'auto' });
    // c_ncr exists with system_id as INTEGER, so the diff wants a recreate it is not allowed to do.
    await adapter.exec(`CREATE TABLE "c_ncr" ("system_id" INTEGER)`);
    await expect(runMigration(adapter, v2, { mode: 'auto' })).rejects.toThrow();
    const task = (await introspect(adapter)).tables.find((t) => t.name === 'c_work_task');
    expect(task?.columns.map((c) => c.name)).not.toContain('c_qty_installed');
  });

  it('planMigration never executes', async () => {
    const plan = await planMigration(adapter, v1);
    expect(plan.hasOperations).toBe(true);
    expect((await introspect(adapter)).tables).toEqual([]);
  });
});
