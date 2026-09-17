import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('description');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function openDb() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const put = (id: string, wo: number, qty: number, description = '') =>
    db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: id, wo_no: wo, c_qty_installed: qty, description, sync_seq: 1, system_removed: 0 });
    });
  return { db, put };
}

/** Waits for the microtask + query round-trip a live query needs to deliver. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('LiveQuery', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('delivers the first result to a subscriber', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const seen: unknown[][] = [];
    query.subscribe((rows) => seen.push(rows));
    await settle();

    expect(seen).toEqual([[{ system_id: 'A', c_qty_installed: 1 }]]);
    query.close();
  });

  it('re-runs when a row in its scope is written', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const seen: unknown[][] = [];
    query.subscribe((rows) => seen.push(rows));
    await settle();

    await opened.put('A', 3188, 5);
    await settle();

    expect(seen).toHaveLength(2);
    expect(seen[1]).toEqual([{ system_id: 'A', c_qty_installed: 5 }]);
    query.close();
  });

  it('does not re-run for a write in a foreign scope', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);

    const query = db.live({
      sql: 'SELECT system_id FROM c_work_task WHERE wo_no = ?',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    listener.mockClear();

    await opened.put('Z', 4000, 1);
    await settle();

    expect(listener).not.toHaveBeenCalled();
    query.close();
  });

  it('re-runs when the writer could not name the rows', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);

    const query = db.live({
      sql: 'SELECT system_id FROM c_work_task WHERE wo_no = ?',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    listener.mockClear();

    // Deleting the row the query returns is a real change to its result, so
    // the unnamed-row invalidation should still make it through to the
    // subscriber, not merely trigger a silent requery.
    await db.execute('DELETE FROM c_work_task', [], { invalidates: ['c_work_task'] });
    await settle();

    expect(listener).toHaveBeenCalledTimes(1);
    query.close();
  });

  it('stops delivering after close and after unsubscribe', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);

    const query = db.live({
      sql: 'SELECT system_id FROM c_work_task',
      reads: [{ table: 'c_work_task' }],
      key: 'system_id',
    });
    const listener = vi.fn();
    const stop = query.subscribe(listener);
    await settle();
    expect(listener).toHaveBeenCalledTimes(1);
    stop();

    await opened.put('B', 4000, 1);
    await settle();
    expect(listener).toHaveBeenCalledTimes(1);

    query.close();
    await opened.put('C', 5000, 1);
    await settle();
    expect(listener).toHaveBeenCalledTimes(1);
  });

  it('does not emit again when a write in scope changes no selected column', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1, 'first');

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    expect(listener).toHaveBeenCalledTimes(1);

    // Same wo_no (in scope) and same qty (the only other selected column), but a
    // different description — an unselected column — so the query's result is
    // byte-for-byte identical even though the write matched the query's scope.
    await opened.put('A', 3188, 1, 'second');
    await settle();

    expect(listener).toHaveBeenCalledTimes(1);
    query.close();
  });

  it('exposes the latest rows through snapshot()', async () => {
    const opened = await openDb();
    db = opened.db;
    await opened.put('A', 3188, 1);
    const query = db.live<{ system_id: string }>({
      sql: 'SELECT system_id FROM c_work_task',
      reads: [{ table: 'c_work_task' }],
      key: 'system_id',
    });
    expect(query.snapshot()).toEqual([]);
    await query.refresh();
    expect(query.snapshot()).toEqual([{ system_id: 'A' }]);
    query.close();
  });
});
