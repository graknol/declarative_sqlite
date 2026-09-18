import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime } from './runtime';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('createSyncRuntime', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('wires overlay and draft holds into every live query', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);
    const sync = await createSyncRuntime({ db, transport, deviceId: 'ipad' });

    await sync.pull.pull('c_work_task', { wo_no: 3188 });

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ?',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const seen: Array<Array<{ c_qty_installed: number }>> = [];
    query.subscribe((rows) => seen.push(rows));
    await settle();
    expect(seen.at(-1)?.[0]?.c_qty_installed).toBe(1);

    await sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await settle();
    expect(seen.at(-1)?.[0]?.c_qty_installed).toBe(10);

    sync.drafts.begin('c_work_task', 'A', 'c_qty_installed', 10);
    sync.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    await query.refresh();
    expect(seen.at(-1)?.[0]?.c_qty_installed).toBe(12);

    query.close();
    sync.close();
  });

  it('loads the outbox index on creation so a restart keeps overlaying', async () => {
    const adapter = new MemoryAdapter();
    db = await Database.open({ schema: testSchema(), adapter });
    const transport = new FakeTransport();
    const first = await createSyncRuntime({ db, transport, deviceId: 'ipad' });
    transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);
    await first.pull.pull('c_work_task', { wo_no: 3188 });
    await first.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    first.close();

    const second = await createSyncRuntime({ db, transport, deviceId: 'ipad' });
    expect(second.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 10 });
    second.close();
  });

  it('purges settled outbox entries older than retentionDays on startup, but keeps recent ones', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new FakeTransport();
    await db.execute(
      `INSERT INTO outbox (id, table_name, system_id, column_name, old_value, new_value, changed_at, status, group_id)
       VALUES ('old', 'c_work_task', 'A', 'c_qty_installed', 'null', '1', '2026-01-01T00:00:00.000Z', 'applied', 'g'),
              ('recent', 'c_work_task', 'A', 'c_qty_installed', 'null', '2', '2026-09-17T00:00:00.000Z', 'noop', 'g')`,
    );

    const sync = await createSyncRuntime({ db, transport, deviceId: 'ipad', retentionDays: 7, clock: () => new Date('2026-09-18T00:00:00.000Z') });

    const remaining = (await sync.outbox.entries()).map((e) => e.id).sort();
    expect(remaining).toEqual(['recent']);
    sync.close();
  });
});
