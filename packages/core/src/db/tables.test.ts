import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from './database';
import { createServerWriteCapability, serverWriter } from './server-truth';
import type { InvalidationEvent } from './invalidation-bus';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('local_prefs', (t) => {
    t.text('key').notNull('');
    t.text('value');
  });
  return s.build();
}

describe('db.tables', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('inserts, reads, updates and deletes a local table', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const prefs = db.tables['local_prefs'];
    if (!prefs || !('insert' in prefs)) throw new Error('local_prefs should be writable');

    await prefs.insert({ system_id: 'p1', key: 'theme', value: 'dark' });
    expect(await prefs.get('p1')).toMatchObject({ key: 'theme', value: 'dark' });

    expect(await prefs.update('p1', { value: 'light' })).toBe(1);
    expect(await prefs.get('p1')).toMatchObject({ value: 'light' });

    await prefs.upsert({ system_id: 'p2', key: 'lang', value: 'nb' });
    expect(await prefs.get('p2')).toBeDefined();

    expect(await prefs.delete('p1')).toBe(1);
    expect(await prefs.get('p1')).toBeUndefined();
  });

  it('exposes no write methods at all on a synced table', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const task = db.tables['c_work_task'];
    expect(task && 'get' in task).toBe(true);
    expect(task && 'insert' in task).toBe(false);
    expect(task && 'update' in task).toBe(false);
    expect(task && 'delete' in task).toBe(false);
  });

  it('reports the row key and scope of every write', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));

    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, system_removed: 0, sync_seq: 10 });
    });

    expect(events).toHaveLength(1);
    expect(events[0]?.tables.get('c_work_task')?.get('A')).toEqual({ wo_no: 3188 });
  });

  it('server writer upsert replaces only the columns it is given', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, system_removed: 0, sync_seq: 10 });
    });
    await db.transaction(async (tx) => {
      await writer.setColumns(tx, 'c_work_task', 'A', { c_qty_installed: 9 });
    });
    expect(await db.queryOne('SELECT wo_no, c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      wo_no: 3188,
      c_qty_installed: 9,
    });
  });

  it('refuses a forged capability', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const database = db;
    expect(() => serverWriter(database, {} as ReturnType<typeof createServerWriteCapability>)).toThrow(/capability/i);
  });

  it('looks up a row scope even when the patch does not carry the scope columns', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const writer = serverWriter(db, createServerWriteCapability());
    await db.transaction(async (tx) => {
      await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 5, system_removed: 0, sync_seq: 10 });
    });

    const events: InvalidationEvent[] = [];
    db.invalidations.subscribe((event) => events.push(event));
    await db.transaction(async (tx) => {
      await writer.setColumns(tx, 'c_work_task', 'A', { c_qty_installed: 6 });
    });
    expect(events[0]?.tables.get('c_work_task')?.get('A')).toEqual({ wo_no: 3188 });
  });

  it('rejects write methods on a synced table at compile time, not just at runtime', async () => {
    type AppRows = {
      c_work_task: { wo_no: number; c_qty_installed: number };
      local_prefs: { key: string; value: string };
    };
    const typed = await Database.open<AppRows, 'c_work_task'>({ schema: testSchema(), adapter: new MemoryAdapter() });
    db = typed;
    const task = typed.tables.c_work_task;
    expect('insert' in task).toBe(false);
    // Referenced, not called: at runtime the property is simply absent (see the
    // 'exposes no write methods' test above), so this only needs to prove the
    // type system rejects it too — a cast could not rescue the caller.
    // @ts-expect-error a synced table's API has no insert method
    void task.insert;
    // @ts-expect-error nor update
    void task.update;
    // @ts-expect-error nor delete
    void task.delete;
  });

  it('binds values rather than concatenating them, even when a value contains a quote', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const prefs = db.tables['local_prefs'];
    if (!prefs || !('insert' in prefs)) throw new Error('local_prefs should be writable');

    const tricky = `O'Brien said "hi"; DROP TABLE local_prefs; --`;
    await prefs.insert({ system_id: `p'1`, key: 'note', value: tricky });
    expect(await prefs.get(`p'1`)).toMatchObject({ key: 'note', value: tricky });

    expect(await prefs.update(`p'1`, { value: `it's fine` })).toBe(1);
    expect(await prefs.get(`p'1`)).toMatchObject({ value: `it's fine` });

    // the table must still exist and be queryable — a naive string-concatenation
    // implementation would have let the embedded `DROP TABLE` execute above.
    expect(await db.queryOne('SELECT COUNT(*) as n FROM local_prefs')).toEqual({ n: 1 });
  });
});
