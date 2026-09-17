import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { CursorStore } from './cursor-store';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => t.real('wo_no')).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

describe('CursorStore', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('starts at zero for an unknown scope', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    expect(await new CursorStore(db).get('c_work_task', { wo_no: 3188 })).toBe(0);
  });

  it('stores a cursor per scope', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', { wo_no: 3188 }, 184240);
    await cursors.set('c_work_task', { wo_no: 4000 }, 12);

    expect(await cursors.get('c_work_task', { wo_no: 3188 })).toBe(184240);
    expect(await cursors.get('c_work_task', { wo_no: 4000 })).toBe(12);
  });

  it('never moves a cursor backwards', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', { wo_no: 3188 }, 500);
    await cursors.set('c_work_task', { wo_no: 3188 }, 100);
    expect(await cursors.get('c_work_task', { wo_no: 3188 })).toBe(500);
  });

  it('keeps a full-table cursor apart from a scoped one', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', undefined, 9);
    await cursors.set('c_work_task', { wo_no: 3188 }, 20);
    expect(await cursors.get('c_work_task', undefined)).toBe(9);
    const rows = await cursors.forTable('c_work_task');
    expect(rows.map((r) => r.scopeKey).sort()).toEqual(['c_work_task|*', 'c_work_task|WO_NO:3188']);
  });

  it('reads the scope back out of a stored cursor', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', { wo_no: 3188 }, 20);
    expect((await cursors.all())[0]?.scope).toEqual({ wo_no: '3188' });
  });

  it('resets a cursor to zero', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const cursors = new CursorStore(db);
    await cursors.set('c_work_task', { wo_no: 3188 }, 20);
    await cursors.reset('c_work_task', { wo_no: 3188 });
    expect(await cursors.get('c_work_task', { wo_no: 3188 })).toBe(0);
  });

  it('uses the injected clock to timestamp synced_at', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const fixedDate = new Date('1999-12-31T23:59:59Z');
    const expectedSyncedAt = fixedDate.toISOString();
    const cursors = new CursorStore(db, { clock: () => fixedDate });

    await cursors.set('c_work_task', { wo_no: 3188 }, 100);

    const rows = await cursors.all();
    const row = rows.find(
      (r) => r.table === 'c_work_task' && r.scope !== undefined && r.scope['wo_no'] === '3188',
    );
    expect(row).toBeDefined();
    expect(row?.syncedAt).toBe(expectedSyncedAt);
  });
});
