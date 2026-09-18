import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime, type SyncRuntime } from './runtime';

/**
 * Spec §9's race scenarios, each proven end to end against a real in-memory
 * SQLite database, the real assembled sync runtime, and a scripted server.
 * Nothing here is a unit test of one layer; every scenario drives the stack
 * the way the app actually would (drafts, outbox, pull, push) and asserts on
 * what a user or another device would observe.
 */

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
    t.text('internal_remark');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function scene() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const transport = new FakeTransport();
  transport.seed('C_WORK_TASK', [
    { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED', INTERNAL_REMARK: null } },
    { id: 'B', data: { WO_NO: 3188, C_QTY_INSTALLED: 2, ROWSTATE: 'RELEASED', INTERNAL_REMARK: null } },
  ]);
  const sync = await createSyncRuntime({ db, transport, deviceId: 'ipad-test', debounceMs: 10 });
  await sync.pull.pull('c_work_task', { wo_no: 3188 });
  return { db, transport, sync };
}

describe('sync scenarios', () => {
  let db: Database | undefined;
  let sync: SyncRuntime | undefined;

  afterEach(async () => {
    sync?.close();
    await db?.close();
    db = undefined;
    sync = undefined;
  });

  it('pull during draft: the typed value stays, siblings update', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    s.sync.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.sync.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);

    s.transport.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 7, ROWSTATE: 'WORKSTARTED' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });

    expect(s.sync.drafts.get('c_work_task', 'A', 'c_qty_installed')).toBe(12);
    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 1, rowstate: 'WORKSTARTED',
    });
  });

  it('pull between record() and the push answer: the pending column is untouched', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    await s.sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    s.transport.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 7, ROWSTATE: 'WORKSTARTED' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });

    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10, rowstate: 'WORKSTARTED',
    });

    await s.sync.push.pushNow();
    expect(s.sync.outbox.pendingColumns('c_work_task', 'A').size).toBe(0);
  });

  it('rejected change: the entry stays visible and the local value reverts on the next pull', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;
    s.transport.reject('C_WORK_TASK', 'ROWSTATE', 'CBADSTATE: not a state this LU can act on');

    await s.sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'CANCELLED' } });
    await s.sync.push.pushNow();

    const rejected = await s.sync.outbox.entries({ status: 'rejected' });
    expect(rejected).toHaveLength(1);
    expect(rejected[0]?.errorText).toContain('CBADSTATE');

    s.transport.serverEdit('C_WORK_TASK', 'A', { ROWSTATE: 'RELEASED' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(await db.queryOne('SELECT rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'RELEASED' });
  });

  it('tombstone during edit: the row survives until the draft ends, then the push says CNOROW', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    s.sync.drafts.begin('c_work_task', 'A', 'internal_remark', null);
    s.sync.drafts.set('c_work_task', 'A', 'internal_remark', 'sjekket');

    s.transport.tombstone('C_WORK_TASK', 'A');
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeDefined();

    await s.sync.drafts.end('c_work_task', 'A', 'internal_remark');
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();

    await s.sync.push.pushNow();
    const entries = await s.sync.outbox.entries({ status: 'rejected' });
    expect(entries[0]?.errorText).toContain('CNOROW');
  });

  it('two devices interleaved: the later arrival stands and both devices converge', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    await s.sync.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    s.transport.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 99 }); // the other device got there first
    await s.sync.push.pushNow();                                        // ours arrives later and wins

    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 10 });
  });

  it('out-of-order arrival: the window brings back a row that committed behind the cursor', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    await s.sync.cursors.set('c_work_task', { wo_no: 3188 }, 900);
    s.transport.serverEdit('C_WORK_TASK', 'B', { C_QTY_INSTALLED: 42 });

    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['B'])).toEqual({ c_qty_installed: 42 });
  });

  it('a 200-row page commits once', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;
    s.transport.seed('C_WORK_TASK', Array.from({ length: 200 }, (_, i) => ({ id: `n-${i}`, data: { WO_NO: 3188, C_QTY_INSTALLED: i } })));

    let events = 0;
    db.invalidations.subscribe(() => {
      events++;
    });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { limit: 500 });

    // The row writes and the cursor advance for one page land inside the same
    // transaction (PullApplier.applyPage runs the cursor update before the
    // transaction commits), so one page is one commit and therefore exactly
    // one invalidation event — confirmed independently by
    // pull-applier.test.ts's "commits a 200-row page as one transaction and
    // one invalidation".
    expect(events).toBe(1);
    expect(await db.query('SELECT system_id FROM c_work_task')).toHaveLength(202);
  });

  it('a live query is not re-run for a foreign scope', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;
    s.transport.seed('C_WORK_TASK', [{ id: 'Z', data: { WO_NO: 4000, C_QTY_INSTALLED: 1 } }]);

    const query = db.live({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    let emissions = 0;
    query.subscribe(() => {
      emissions++;
    });
    await settle();
    const before = emissions;

    await s.sync.pull.pull('c_work_task', { wo_no: 4000 });
    await settle();

    expect(emissions).toBe(before);
    query.close();
  });

  it('an identical result is not emitted', async () => {
    const s = await scene();
    db = s.db;
    sync = s.sync;

    const query = db.live({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    let emissions = 0;
    query.subscribe(() => {
      emissions++;
    });
    await settle();
    const before = emissions;

    s.transport.serverEdit('C_WORK_TASK', 'A', { INTERNAL_REMARK: 'irrelevant to this query' });
    await s.sync.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    await settle();

    expect(emissions).toBe(before);
    query.close();
  });
});
