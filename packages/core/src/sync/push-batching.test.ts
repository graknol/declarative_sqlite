import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { FakeTransport } from '../testing/fake-transport';
import { Outbox } from './outbox';
import { Drafts } from './drafts';
import { CursorStore } from './cursor-store';
import { PullApplier } from './pull-applier';
import { PushService } from './push-service';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup(options: { maxChangesPerBatch?: number } = {}) {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  const drafts = new Drafts(db, outbox, writer);
  const applier = new PullApplier(db, writer, outbox, drafts, new CursorStore(db));
  const transport = new FakeTransport();
  const push = new PushService(db, transport, outbox, applier, { deviceId: 'ipad-test', debounceMs: 2000, ...options });

  await db.transaction(async (tx) => {
    for (const id of ['A', 'B']) {
      await writer.upsert(tx, 'c_work_task', { system_id: id, wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 1, system_removed: 0 });
    }
  });
  transport.seed('C_WORK_TASK', [
    { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } },
    { id: 'B', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } },
  ]);
  return { db, outbox, transport, push };
}

describe('PushService batching', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('sends the wire shapes the API expects', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await s.push.pushNow();

    const batch = s.transport.pushes[0];
    expect(batch?.deviceId).toBe('ipad-test');
    expect(batch?.batchId.length).toBeLessThanOrEqual(36);
    expect(batch?.changes[0]).toMatchObject({ table: 'C_WORK_TASK', id: 'A', column: 'C_QTY_INSTALLED', old: 1, new: 10 });
    expect(typeof batch?.changes[0]?.changedAt).toBe('string');
  });

  it('keeps a change group whole and in recorded order', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'WORKSTARTED', c_qty_installed: 10 } });
    await s.push.pushNow();
    const columns = s.transport.pushes[0]?.changes.map((c) => c.column);
    expect(columns).toEqual(['ROWSTATE', 'C_QTY_INSTALLED']);
  });

  it('never splits a group across batches at the cap', async () => {
    const s = await setup({ maxChangesPerBatch: 3 });
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' } });
    await s.outbox.record({ table: 'c_work_task', systemId: 'B', changes: { c_qty_installed: 20, rowstate: 'WORKSTARTED' } });

    await s.push.pushNow();

    expect(s.transport.pushes).toHaveLength(2);
    expect(s.transport.pushes[0]?.changes.map((c) => c.id)).toEqual(['A', 'A']);
    expect(s.transport.pushes[1]?.changes.map((c) => c.id)).toEqual(['B', 'B']);
  });

  it('does nothing when there is nothing pending', async () => {
    const s = await setup();
    db = s.db;
    expect(await s.push.pushNow()).toMatchObject({ batches: 0 });
    expect(s.transport.pushes).toHaveLength(0);
  });

  it('debounces scheduled pushes into one', async () => {
    vi.useFakeTimers();
    try {
      const s = await setup();
      db = s.db;
      await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
      s.push.schedule();
      s.push.schedule();
      s.push.schedule();
      await vi.advanceTimersByTimeAsync(1999);
      expect(s.transport.pushes).toHaveLength(0);
      await vi.advanceTimersByTimeAsync(2);
      expect(s.transport.pushes).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('reuses the batch id when a network error made the outcome unknown', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    s.transport.failNextPush();

    await s.push.pushNow();
    expect((await s.outbox.pending()).map((e) => e.status)).toEqual(['pending']);

    await s.push.pushNow();
    expect(s.transport.pushes).toHaveLength(2);
    expect(s.transport.pushes[0]?.batchId).toBe(s.transport.pushes[1]?.batchId);
  });

  it('only sends pending entries, never ones already sending', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'other-batch');
    expect(await s.push.pushNow()).toMatchObject({ batches: 0 });
  });
});
