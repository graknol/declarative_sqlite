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

async function setup(options: Partial<{ isTerminalError: (e: unknown) => boolean }> = {}) {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  const drafts = new Drafts(db, outbox, writer);
  const cursors = new CursorStore(db);
  const applier = new PullApplier(db, writer, outbox, drafts, cursors);
  const transport = new FakeTransport();
  const push = new PushService(db, transport, outbox, applier, { deviceId: 'ipad', debounceMs: 1, ...options });

  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 50, system_removed: 0 });
  });
  transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } }]);
  return { db, outbox, transport, push, cursors };
}

describe('PushService answers', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('marks applied entries and lets the returned row land', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

    const outcome = await s.push.pushNow();

    expect(outcome).toMatchObject({ applied: 1, rejected: 0 });
    expect(s.outbox.pendingColumns('c_work_task', 'A').size).toBe(0);
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 10 });
  });

  it('skips an answer row whose seq is not above the local one', async () => {
    const s = await setup();
    db = s.db;
    await db.execute('UPDATE c_work_task SET sync_seq = 100000 WHERE system_id = ?', ['A']);
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

    await s.push.pushNow();

    // The local row keeps the value the outbox wrote; the tick-driven pull brings the final state.
    expect(await db.queryOne('SELECT c_qty_installed, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10, sync_seq: 100000,
    });
  });

  it('never moves a cursor from a push answer', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await s.push.pushNow();
    expect(await s.cursors.get('c_work_task', { wo_no: 3188 })).toBe(0);
  });

  it('keeps a rejected entry visible with its message and reports it', async () => {
    const s = await setup();
    db = s.db;
    s.transport.reject('C_WORK_TASK', 'ROWSTATE', 'CBADSTATE: this rowstate cannot be pushed');
    const rejected = vi.fn();
    s.push.onRejected(rejected);

    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'CANCELLED' } });
    const outcome = await s.push.pushNow();

    expect(outcome.rejected).toBe(1);
    expect(rejected).toHaveBeenCalled();
    const entries = await s.outbox.entries({ status: 'rejected' });
    expect(entries[0]?.errorText).toContain('CBADSTATE');
  });

  it('does not resend a rejected entry on the next push', async () => {
    const s = await setup();
    db = s.db;
    s.transport.reject('C_WORK_TASK', 'ROWSTATE', 'CBADSTATE: no');
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'CANCELLED' } });
    await s.push.pushNow();
    await s.push.pushNow();
    expect(s.transport.pushes).toHaveLength(1);
  });

  it('answers noop without changing anything', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 1 } });
    const outcome = await s.push.pushNow();
    expect(outcome).toMatchObject({ noop: 1 });
    expect((await s.outbox.entries())[0]?.status).toBe('noop');
  });

  it('backs off 5 s, 30 s, 2 min across repeated network failures', async () => {
    vi.useFakeTimers();
    try {
      const s = await setup();
      db = s.db;
      await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

      s.transport.failNextPush();
      await s.push.pushNow();
      expect(s.push.status()).toMatchObject({ attempt: 1, online: false });
      const first = s.push.status().nextRetryAt ?? 0;

      s.transport.failNextPush();
      await vi.advanceTimersByTimeAsync(5001);
      expect(s.push.status().attempt).toBe(2);
      const second = s.push.status().nextRetryAt ?? 0;
      expect(second - first).toBeGreaterThanOrEqual(25000);

      await vi.advanceTimersByTimeAsync(30001);
      expect(s.push.status()).toMatchObject({ attempt: 0, online: true });
      expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 10 });
    } finally {
      vi.useRealTimers();
    }
  });

  it('retries immediately when the app says it is online again', async () => {
    vi.useFakeTimers();
    try {
      const s = await setup();
      db = s.db;
      await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
      s.transport.failNextPush();
      await s.push.pushNow();

      s.push.notifyOnline();
      await vi.advanceTimersByTimeAsync(1);
      expect(s.transport.pushes).toHaveLength(2);
    } finally {
      vi.useRealTimers();
    }
  });

  it('marks the batch rejected for a terminal error instead of looping', async () => {
    const s = await setup({ isTerminalError: () => true });
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    s.transport.failNextPush(new Error('HTTP 400 bad request'));

    await s.push.pushNow();

    const entries = await s.outbox.entries();
    expect(entries[0]).toMatchObject({ status: 'rejected' });
    expect(entries[0]?.errorText).toContain('400');
  });
});
