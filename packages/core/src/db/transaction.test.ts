import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from './database';
import type { InvalidationEvent } from './invalidation-bus';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

describe('Database.transaction', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('commits and emits exactly one event for many writes', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));

    await db.transaction(async (tx) => {
      for (const id of ['A', 'B', 'C']) {
        await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, [id, 3188]);
        tx.markWritten('c_work_task', id, { wo_no: 3188 });
      }
    });

    expect(events).toHaveLength(1);
    expect([...(events[0]?.tables.get('c_work_task') ?? new Map()).keys()]).toEqual(['A', 'B', 'C']);
  });

  it('rolls back and emits nothing when the work throws', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));

    await expect(
      db.transaction(async (tx) => {
        await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, ['A', 3188]);
        tx.markWritten('c_work_task', 'A', { wo_no: 3188 });
        throw new Error('nope');
      }),
    ).rejects.toThrow('nope');

    expect(await db.query('SELECT system_id FROM c_work_task')).toEqual([]);
    expect(events).toEqual([]);
  });

  it('emits nothing when a transaction wrote nothing', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));
    await db.transaction(async (tx) => {
      await tx.query('SELECT 1');
    });
    expect(events).toEqual([]);
  });

  it('serialises overlapping transactions instead of interleaving BEGIN', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const order: string[] = [];

    const first = db.transaction(async (tx) => {
      order.push('first-start');
      await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, ['A', 1]);
      await new Promise((resolve) => setTimeout(resolve, 10));
      order.push('first-end');
    });
    const second = db.transaction(async (tx) => {
      order.push('second-start');
      await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, ['B', 1]);
      order.push('second-end');
    });

    await Promise.all([first, second]);
    expect(order).toEqual(['first-start', 'first-end', 'second-start', 'second-end']);
    expect(await db.query('SELECT system_id FROM c_work_task ORDER BY system_id')).toHaveLength(2);
  });

  it('returns the work function result', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    expect(await db.transaction(async () => 42)).toBe(42);
  });
});
