import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 5, system_removed: 0 });
  });
  return { db, outbox };
}

describe('Outbox statuses', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('lists pending entries oldest first and indexes their columns', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });

    const pending = await s.outbox.pending();
    expect(pending.map((e) => e.columnName).sort()).toEqual(['c_qty_installed', 'rowstate']);
    expect([...s.outbox.pendingColumns('c_work_task', 'A')].sort()).toEqual(['c_qty_installed', 'rowstate']);
    expect(s.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 10 });
  });

  it('marks entries sending with a batch id and keeps them in the index', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const [entry] = await s.outbox.pending();
    await s.outbox.markSending([entry!.id], 'batch-1');

    expect(await s.outbox.pending()).toEqual([]);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('c_qty_installed')).toBe(true);
    expect((await s.outbox.counts()).sending).toBe(1);
  });

  it('applies results by order index and leaves the index clean', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });
    const entries = await s.outbox.pending();
    const order = entries.map((e) => e.id);
    await s.outbox.markSending(order, 'batch-1');

    await s.outbox.applyResults(
      'batch-1',
      [
        { index: 0, result: 'applied', error: null },
        { index: 1, result: 'rejected', error: 'WTCERR2: not allowed' },
      ],
      order,
    );

    const all = await s.outbox.entries();
    expect(all.find((e) => e.id === order[0])?.status).toBe('applied');
    expect(all.find((e) => e.id === order[1])).toMatchObject({ status: 'rejected', errorText: 'WTCERR2: not allowed' });
    expect(s.outbox.pendingColumns('c_work_task', 'A').size).toBe(0);
    expect(await s.outbox.counts()).toMatchObject({ pending: 0, sending: 0, rejected: 1 });
  });

  it('returns a sending batch to pending after a network error', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'batch-1');

    await s.outbox.resetSending('batch-1');

    expect((await s.outbox.pending()).map((e) => e.id)).toEqual(order);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('c_qty_installed')).toBe(true);
  });

  it('retries a rejected entry and discards another', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'batch-1');
    await s.outbox.applyResults('batch-1', order.map((_, index) => ({ index, result: 'rejected' as const, error: 'no' })), order);

    await s.outbox.retry(order[0]!);
    await s.outbox.discard(order[1]!);

    expect((await s.outbox.pending()).map((e) => e.id)).toEqual([order[0]]);
    expect((await s.outbox.entries()).map((e) => e.id)).toEqual([order[0]]);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('c_qty_installed')).toBe(true);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('rowstate')).toBe(false);
  });

  it('leaves entries with no result in the batch back at pending', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'batch-1');
    await s.outbox.applyResults('batch-1', [{ index: 0, result: 'applied', error: null }], order);
    expect((await s.outbox.pending()).map((e) => e.id)).toEqual([order[1]]);
  });

  it('purges settled entries older than the retention window and keeps the rest', async () => {
    const s = await setup();
    db = s.db;
    await db.execute(
      `INSERT INTO outbox (id, table_name, system_id, column_name, old_value, new_value, changed_at, status, group_id)
       VALUES ('old', 'c_work_task', 'A', 'rowstate', 'null', '"X"', '2026-08-01T00:00:00.000Z', 'applied', 'g'),
              ('recent', 'c_work_task', 'A', 'rowstate', 'null', '"Y"', '2026-09-16T00:00:00.000Z', 'applied', 'g'),
              ('open', 'c_work_task', 'A', 'rowstate', 'null', '"Z"', '2026-08-01T00:00:00.000Z', 'rejected', 'g')`,
    );
    const purged = await s.outbox.purgeOlderThan(30, new Date('2026-09-17T00:00:00Z'));
    expect(purged).toBe(1);
    expect((await s.outbox.entries()).map((e) => e.id).sort()).toEqual(['open', 'recent']);
  });

  it('ignores a stale applyResults for a superseded batch and keeps the index in sync with the table', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const [entry] = await s.outbox.pending();
    const id = entry!.id;

    await s.outbox.markSending([id], 'batch-1');
    await s.outbox.resetSending('batch-1');
    await s.outbox.markSending([id], 'batch-2');

    // A late answer for the superseded first batch arrives after the entry
    // has already moved on to batch-2.
    await s.outbox.applyResults('batch-1', [{ index: 0, result: 'applied', error: null }], [id]);

    const all = await s.outbox.entries();
    expect(all.find((e) => e.id === id)).toMatchObject({ status: 'sending', batchId: 'batch-2' });
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('c_qty_installed')).toBe(true);
  });

  it('rebuilds the index from the table on load', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

    const reloaded = new Outbox(s.db, serverWriter(s.db, createServerWriteCapability()));
    await reloaded.load();
    expect(reloaded.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 10 });
  });
});
