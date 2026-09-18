import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox, OutboxError } from './outbox';
import { ValueTooLongError } from './wire';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
    t.text('internal_remark');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('local_prefs', (t) => t.text('value'));
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer, { clock: () => new Date('2026-09-17T09:12:31Z') });
  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', {
      system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', internal_remark: null, sync_seq: 5, system_removed: 0,
    });
  });
  return { db, outbox };
}

describe('Outbox.record', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('writes the local columns and the outbox rows in one transaction', async () => {
    const s = await setup();
    db = s.db;
    const groupId = await s.outbox.record({
      table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' },
    });

    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10, rowstate: 'WORKSTARTED',
    });
    const entries = await db.query<{ column_name: string; old_value: string; new_value: string; status: string; group_id: string }>(
      'SELECT column_name, old_value, new_value, status, group_id FROM outbox ORDER BY column_name',
    );
    expect(entries).toEqual([
      { column_name: 'c_qty_installed', old_value: '1', new_value: '10', status: 'pending', group_id: groupId },
      { column_name: 'rowstate', old_value: '"RELEASED"', new_value: '"WORKSTARTED"', status: 'pending', group_id: groupId },
    ]);
  });

  it('records the old value it saw, including null', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { internal_remark: 'sjekket' } });
    expect(await db.queryOne('SELECT old_value FROM outbox')).toEqual({ old_value: 'null' });
  });

  it('gives every recorded change the same group id and a fresh one per call', async () => {
    const s = await setup();
    db = s.db;
    const first = await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 2 } });
    const second = await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 3 } });
    expect(first).not.toBe(second);
    expect(await db.query('SELECT id FROM outbox')).toHaveLength(2);
  });

  it('emits one invalidation carrying the row and its scope', async () => {
    const s = await setup();
    db = s.db;
    const events: Array<Map<string, unknown>> = [];
    db.invalidations.subscribe((event) => events.push(new Map(event.tables)));
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    expect(events).toHaveLength(1);
    expect(events[0]?.get('c_work_task')).toBeDefined();
    expect(events[0]?.get('outbox')).toBeDefined();
  });

  it('notifies subscribers that the outbox changed', async () => {
    const s = await setup();
    db = s.db;
    const listener = vi.fn();
    s.outbox.subscribe(listener);
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    expect(listener).toHaveBeenCalled();
  });

  it('refuses a table that is not synced', async () => {
    const s = await setup();
    db = s.db;
    await expect(s.outbox.record({ table: 'local_prefs', systemId: 'x', changes: { value: '1' } })).rejects.toThrow(OutboxError);
  });

  it('refuses a row that does not exist locally', async () => {
    const s = await setup();
    db = s.db;
    await expect(s.outbox.record({ table: 'c_work_task', systemId: 'GONE', changes: { c_qty_installed: 1 } })).rejects.toThrow(/GONE/);
  });

  it('refuses a column the schema does not declare and an empty change set', async () => {
    const s = await setup();
    db = s.db;
    await expect(s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { nope: 1 } })).rejects.toThrow(/nope/);
    await expect(s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: {} })).rejects.toThrow(/no changes/i);
  });

  it('refuses a value wider than the server accepts, leaving nothing behind', async () => {
    const s = await setup();
    db = s.db;
    await expect(
      s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { internal_remark: 'x'.repeat(4100) } }),
    ).rejects.toThrow(ValueTooLongError);
    expect(await db.query('SELECT id FROM outbox')).toEqual([]);
  });

  it('refuses a change group larger than one batch can carry', async () => {
    const s = await setup();
    db = s.db;
    const changes: Record<string, unknown> = {};
    for (let i = 0; i < 501; i++) changes[`col_${i}`] = i;
    await expect(s.outbox.record({ table: 'c_work_task', systemId: 'A', changes })).rejects.toThrow(/group/i);
  });
});

/**
 * `db.transaction()` is reentrant: called while one is open it hands the body
 * the same `Transaction` and resolves as soon as that body ends, long before
 * the outer COMMIT is decided. Every in-memory mutation the outbox makes must
 * therefore hang off `tx.onCommit`, or a later failure in the enclosing
 * transaction leaves the index claiming changes the tables never kept — a split
 * only a reload repairs.
 */
describe('Outbox inside an enclosing transaction', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('leaves nothing pending when a later step of the same outer transaction fails', async () => {
    const s = await setup();
    db = s.db;

    await expect(
      db.transaction(async () => {
        await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 1 } });
        // Something else in the same outer transaction fails after record()'s
        // own nested call has already "resolved" from record()'s point of view.
        throw new Error('simulated failure later in the same outer transaction');
      }),
    ).rejects.toThrow('simulated failure later in the same outer transaction');

    // The whole outer transaction rolled back, so nothing should be pending.
    expect(s.outbox.pendingColumns('c_work_task', 'A').size).toBe(0);
    expect(await s.outbox.entries({ status: 'pending' })).toHaveLength(0);
  });

  it('indexes the change when the enclosing transaction does commit', async () => {
    const s = await setup();
    db = s.db;

    await db.transaction(async () => {
      await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 7 } });
    });

    expect(s.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 7 });
    expect(await s.outbox.entries({ status: 'pending' })).toHaveLength(1);
  });

  it('keeps a discarded entry in the index when the outer transaction rolls back', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const [entry] = await s.outbox.entries({ status: 'pending' });
    const id = entry?.id ?? '';

    await expect(
      db.transaction(async () => {
        await s.outbox.discard(id);
        throw new Error('simulated failure after discard');
      }),
    ).rejects.toThrow('simulated failure after discard');

    // The DELETE rolled back, so the entry is still there and still pending.
    expect(await s.outbox.entries({ status: 'pending' })).toHaveLength(1);
    expect(s.outbox.pendingColumns('c_work_task', 'A').has('c_qty_installed')).toBe(true);
  });
});
