import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';
import { Drafts } from './drafts';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup() {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  await db.transaction(async (tx) => {
    await writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, c_qty_installed: 1, rowstate: 'RELEASED', sync_seq: 5, system_removed: 0 });
  });
  return { db, outbox, writer, drafts: new Drafts(db, outbox, writer) };
}

describe('Drafts', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('is inactive until a field takes focus', async () => {
    const s = await setup();
    db = s.db;
    expect(s.drafts.isActive('c_work_task', 'A', 'c_qty_installed')).toBe(false);
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    expect(s.drafts.isActive('c_work_task', 'A', 'c_qty_installed')).toBe(true);
    expect(s.drafts.get('c_work_task', 'A', 'c_qty_installed')).toBe(1);
  });

  it('keeps keystrokes and notifies subscribers', async () => {
    const s = await setup();
    db = s.db;
    const listener = vi.fn();
    s.drafts.subscribe(listener);
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    expect(s.drafts.get('c_work_task', 'A', 'c_qty_installed')).toBe(12);
    expect(listener).toHaveBeenCalled();
  });

  it('holds the drafted column at its last emitted value and lets siblings update', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);

    const held = s.drafts.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 7, rowstate: 'WORKSTARTED' }]);
    expect(held[0]).toEqual({ system_id: 'A', c_qty_installed: 1, rowstate: 'WORKSTARTED' });
  });

  it('shows the typed value, not the seed, while typing', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    expect(s.drafts.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 7 }])[0]?.['c_qty_installed']).toBe(12);
  });

  it('only holds the focused column of the focused row', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    const rows = [{ system_id: 'B', c_qty_installed: 9 }];
    expect(s.drafts.apply('c_work_task', rows)).toBe(rows);
    expect([...s.drafts.activeColumns('c_work_task', 'A')]).toEqual(['c_qty_installed']);
    expect(s.drafts.activeColumns('c_work_task', 'B').size).toBe(0);
  });

  it('returns the same array when no draft touches the rows', async () => {
    const s = await setup();
    db = s.db;
    const rows = [{ system_id: 'A', c_qty_installed: 1 }];
    expect(s.drafts.apply('c_work_task', rows)).toBe(rows);
  });

  it('keeps identity when the only drafted column is absent from the row', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'rowstate', 'RELEASED');
    s.drafts.set('c_work_task', 'A', 'rowstate', 'DONE');
    const row = { system_id: 'A', c_qty_installed: 1 };
    const rows = [row];
    const result = s.drafts.apply('c_work_task', rows);
    expect(result).toBe(rows);
    expect(result[0]).toBe(row);
  });
});
