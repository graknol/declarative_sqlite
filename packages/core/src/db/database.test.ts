import { describe, it, expect, afterEach, vi } from 'vitest';
import type { SQLiteAdapter } from '../adapters/adapter';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database, DatabaseError } from './database';
import type { InvalidationEvent } from './invalidation-bus';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.text('rowstate');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('local_prefs', (t) => {
    t.text('key').notNull('');
    t.text('value');
  });
  return s.build();
}

describe('Database', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('opens, migrates and exposes the schema', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    expect(db.schema.tables.map((t) => t.name)).toContain('outbox');
    expect(await db.query('SELECT name FROM sqlite_master WHERE name = ?', ['c_work_task'])).toHaveLength(1);
  });

  it('queries with parameters and returns typed rows', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    await db.execute(`INSERT INTO "local_prefs" ("system_id", "key", "value") VALUES (?, ?, ?)`, ['p1', 'theme', 'dark']);
    const rows = await db.query<{ key: string; value: string }>('SELECT key, value FROM local_prefs WHERE key = ?', ['theme']);
    expect(rows).toEqual([{ key: 'theme', value: 'dark' }]);
    expect(await db.queryOne('SELECT key FROM local_prefs WHERE key = ?', ['missing'])).toBeUndefined();
  });

  it('emits one invalidation for the tables an execute declares', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: string[][] = [];
    db.invalidations.subscribe((event) => events.push([...event.tables.keys()]));
    await db.execute(`INSERT INTO "local_prefs" ("system_id", "key") VALUES (?, ?)`, ['p1', 'a'], { invalidates: ['local_prefs'] });
    expect(events).toEqual([['local_prefs']]);
  });

  it('emits nothing for an execute that declares no tables', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const events: unknown[] = [];
    db.invalidations.subscribe((event) => events.push(event));
    await db.execute(`INSERT INTO "local_prefs" ("system_id", "key") VALUES (?, ?)`, ['p1', 'a']);
    expect(events).toEqual([]);
  });

  it('passes the migration plan to onMigrationPlan in plan mode and creates nothing', async () => {
    const plans: number[] = [];
    db = await Database.open({
      schema: testSchema(),
      adapter: new MemoryAdapter(),
      migrate: 'plan',
      onMigrationPlan: (plan) => plans.push(plan.operations.length),
    });
    expect(plans[0]).toBeGreaterThan(0);
    await expect(db.query('SELECT 1 FROM c_work_task')).rejects.toThrow();
  });

  it('refuses to be used after close', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    await db.close();
    await expect(db.query('SELECT 1')).rejects.toThrow(/closed/i);
    await expect(db.query('SELECT 1')).rejects.toThrow(DatabaseError);
    db = undefined;
  });

  it('a db.execute inside a transaction body does not emit its own event and rolls back with it', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const database = db;
    const events: InvalidationEvent[] = [];
    database.invalidations.subscribe((event) => events.push(event));

    await expect(
      database.transaction(async () => {
        await database.execute(`INSERT INTO "local_prefs" ("system_id", "key") VALUES (?, ?)`, ['p1', 'a'], {
          invalidates: ['local_prefs'],
        });
        throw new Error('nope');
      }),
    ).rejects.toThrow('nope');

    expect(await database.query('SELECT system_id FROM local_prefs')).toEqual([]);
    expect(events).toEqual([]);
  });

  it('an execute queued behind a slow transaction runs after it commits, not during it', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const database = db;
    const order: string[] = [];

    const slow = database.transaction(async (tx) => {
      order.push('tx-start');
      await tx.execute(`INSERT INTO "local_prefs" ("system_id", "key") VALUES (?, ?)`, ['p1', 'a']);
      await new Promise((resolve) => setTimeout(resolve, 10));
      order.push('tx-end');
    });

    const queuedExecute = database
      .execute(`INSERT INTO "local_prefs" ("system_id", "key") VALUES (?, ?)`, ['p2', 'b'])
      .then(() => {
        order.push('execute-done');
      });

    await Promise.all([slow, queuedExecute]);
    expect(order).toEqual(['tx-start', 'tx-end', 'execute-done']);
  });

  it('close() waits for a queued transaction to commit before tearing down the adapter', async () => {
    const adapter = new MemoryAdapter();
    const order: string[] = [];
    const originalClose = adapter.close.bind(adapter);
    const originalRun = adapter.run.bind(adapter);
    adapter.close = async () => {
      order.push('adapter-close');
      await originalClose();
    };
    adapter.run = async (sql, params) => {
      const result = await originalRun(sql, params);
      if (sql.includes('local_prefs')) order.push('insert');
      return result;
    };

    db = await Database.open({ schema: testSchema(), adapter });
    const database = db;

    const slow = database.transaction(async (tx) => {
      await new Promise((resolve) => setTimeout(resolve, 10));
      await tx.execute(`INSERT INTO "local_prefs" ("system_id", "key") VALUES (?, ?)`, ['p1', 'a']);
      tx.markWritten('local_prefs', 'p1');
    });

    const closePromise = database.close();
    await expect(database.query('SELECT 1')).rejects.toThrow('Database is closed');

    await Promise.all([slow, closePromise]);
    expect(order).toEqual(['insert', 'adapter-close']);
    db = undefined;
  });

  it('a failing ROLLBACK is logged but does not swallow the original error', async () => {
    const real = new MemoryAdapter();
    const stub: SQLiteAdapter = {
      open: () => real.open(),
      close: () => real.close(),
      isOpen: () => real.isOpen(),
      all: (sql, params) => real.all(sql, params),
      get: (sql, params) => real.get(sql, params),
      run: (sql, params) => real.run(sql, params),
      export: () => real.export(),
      exec: async (sql: string) => {
        if (sql === 'ROLLBACK') throw new Error('rollback exploded');
        return real.exec(sql);
      },
    };
    db = await Database.open({ schema: testSchema(), adapter: stub });
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});

    await expect(
      db.transaction(async () => {
        throw new Error('body failed');
      }),
    ).rejects.toThrow('body failed');

    expect(consoleError).toHaveBeenCalledWith(expect.stringContaining('[declarative-sqlite]'), expect.any(Error));
    consoleError.mockRestore();
  });
});
