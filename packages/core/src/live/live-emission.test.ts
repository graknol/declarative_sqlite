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
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('live query emissions', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('emits once for a transaction that wrote 200 rows', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    const query = db.live({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    listener.mockClear();

    await db.transaction(async (tx) => {
      for (let i = 0; i < 200; i++) {
        await writer.upsert(tx, 'c_work_task', {
          system_id: `row-${i}`, wo_no: 3188, c_qty_installed: i, sync_seq: i + 1, system_removed: 0,
        });
      }
    });
    await settle();

    expect(listener).toHaveBeenCalledTimes(1);
    expect(listener.mock.calls[0]?.[0]).toHaveLength(200);
    query.close();
  });

  it('does not emit when a write leaves the result identical', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, sync_seq: 1, system_removed: 0 });
    });

    const query = db.live({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ?',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const listener = vi.fn();
    query.subscribe(listener);
    await settle();
    listener.mockClear();

    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, sync_seq: 2, system_removed: 0 });
    });
    await settle();

    expect(listener).not.toHaveBeenCalled();
    query.close();
  });

  it('keeps the identity of rows that did not change between emissions', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      for (const id of ['A', 'B']) {
        await writer.upsert(tx, 'c_work_task', { system_id: id, wo_no: 3188, c_qty_installed: 1, sync_seq: 1, system_removed: 0 });
      }
    });

    const query = db.live<{ system_id: string; c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
      params: [3188],
      reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
      key: 'system_id',
    });
    const emissions: Array<Array<{ system_id: string }>> = [];
    query.subscribe((rows) => emissions.push(rows));
    await settle();

    await db.transaction(async (tx) => {
      await writer.setColumns(tx, 'c_work_task', 'B', { c_qty_installed: 9 });
    });
    await settle();

    expect(emissions).toHaveLength(2);
    expect(emissions[1]?.[0]).toBe(emissions[0]?.[0]); // A untouched, same object
    expect(emissions[1]?.[1]).not.toBe(emissions[0]?.[1]);
    query.close();
  });

  it('applies the installed row transform before emitting', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, sync_seq: 1, system_removed: 0 });
    });

    db.setRowTransform((table, rows) => (table === 'c_work_task' ? rows.map((row) => ({ ...row, c_qty_installed: 99 })) : rows));

    const query = db.live<{ c_qty_installed: number }>({
      sql: 'SELECT system_id, c_qty_installed FROM c_work_task',
      reads: [{ table: 'c_work_task' }],
      key: 'system_id',
    });
    const emissions: Array<Array<{ c_qty_installed: number }>> = [];
    query.subscribe((rows) => emissions.push(rows));
    await settle();

    expect(emissions[0]?.[0]?.c_qty_installed).toBe(99);
    query.close();
  });

  it('respects minInterval by delaying the second emission', async () => {
    vi.useFakeTimers();
    try {
      db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
      const writer = serverWriter(db, createServerWriteCapability());
      const query = db.live({
        sql: 'SELECT system_id, c_qty_installed FROM c_work_task',
        reads: [{ table: 'c_work_task' }],
        key: 'system_id',
        minInterval: 200,
      });
      const listener = vi.fn();
      query.subscribe(listener);
      await vi.advanceTimersByTimeAsync(1);

      await db.transaction(async (tx) => {
        await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 1, c_qty_installed: 1, sync_seq: 1, system_removed: 0 });
      });
      await vi.advanceTimersByTimeAsync(1);
      const afterFirst = listener.mock.calls.length;

      await db.transaction(async (tx) => {
        await writer.setColumns(tx, 'c_work_task', 'A', { c_qty_installed: 2 });
      });
      await vi.advanceTimersByTimeAsync(1);
      expect(listener.mock.calls.length).toBe(afterFirst);

      await vi.advanceTimersByTimeAsync(300);
      expect(listener.mock.calls.length).toBe(afterFirst + 1);
      query.close();
    } finally {
      vi.useRealTimers();
    }
  });
});
