import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from './database';

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
    db = undefined;
  });
});
