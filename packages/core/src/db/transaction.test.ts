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
  s.table('local_note', (t) => {
    t.text('text');
  });
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

  it(
    'a nested db.tables write joins the open transaction instead of hanging',
    async () => {
      db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
      const notes = db.tables['local_note'];
      if (!notes || !('insert' in notes)) throw new Error('local_note should be writable');

      await db.transaction(async () => {
        await notes.insert({ system_id: 'n1', text: 'hi' });
      });

      expect(await notes.get('n1')).toMatchObject({ text: 'hi' });
    },
    { timeout: 5000 },
  );

  it(
    'a nested db.transaction call resolves and returns its own callback result',
    async () => {
      db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
      const outer = db;

      const result = await outer.transaction(async () => outer.transaction(async () => 'nested-value'));

      expect(result).toBe('nested-value');
    },
    { timeout: 5000 },
  );

  it(
    'rolls back a nested write when the outer body throws, and emits no invalidation',
    async () => {
      db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
      const notes = db.tables['local_note'];
      if (!notes || !('insert' in notes)) throw new Error('local_note should be writable');
      const events: InvalidationEvent[] = [];
      db.invalidations.subscribe((event) => events.push(event));

      await expect(
        db.transaction(async () => {
          await notes.insert({ system_id: 'n1', text: 'hi' });
          throw new Error('nope');
        }),
      ).rejects.toThrow('nope');

      expect(await notes.get('n1')).toBeUndefined();
      expect(events).toEqual([]);
    },
    { timeout: 5000 },
  );

  it(
    'one outer transaction with two nested writes emits exactly one event covering both tables',
    async () => {
      db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
      const notes = db.tables['local_note'];
      if (!notes || !('insert' in notes)) throw new Error('local_note should be writable');
      const events: InvalidationEvent[] = [];
      db.invalidations.subscribe((event) => events.push(event));

      await db.transaction(async (tx) => {
        await notes.insert({ system_id: 'n1', text: 'hi' });
        await tx.execute(`INSERT INTO "c_work_task" ("system_id", "wo_no") VALUES (?, ?)`, ['A', 1]);
        tx.markWritten('c_work_task', 'A', { wo_no: 1 });
      });

      expect(events).toHaveLength(1);
      expect([...(events[0]?.tables.keys() ?? [])].sort()).toEqual(['c_work_task', 'local_note']);
    },
    { timeout: 5000 },
  );
});
