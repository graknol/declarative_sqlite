import { describe, it, expect, afterEach } from 'vitest';
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

describe('Drafts.end', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('commits a changed value to the outbox and clears the draft', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);

    expect(await s.drafts.end('c_work_task', 'A', 'c_qty_installed')).toBe('committed');
    expect(s.drafts.isActive('c_work_task', 'A', 'c_qty_installed')).toBe(false);
    expect(s.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 12 });
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 12 });
  });

  it('records nothing when the value did not change', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    expect(await s.drafts.end('c_work_task', 'A', 'c_qty_installed')).toBe('released');
    expect(await db.query('SELECT id FROM outbox')).toEqual([]);
  });

  it('holds a server value for a drafted column and applies it on an unchanged end', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);

    expect(s.drafts.holdServerValue('c_work_task', 'A', 'c_qty_installed', 7)).toBe(true);
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 1 });

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 7 });
  });

  it('drops the held server value when the user changed the column', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.holdServerValue('c_work_task', 'A', 'c_qty_installed', 7);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 12 });
    expect(s.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 12 });
  });

  it('does not hold a server value for a column that is not drafted', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    expect(s.drafts.holdServerValue('c_work_task', 'A', 'rowstate', 'WORKSTARTED')).toBe(false);
  });

  it('holds a tombstone while a draft is open and deletes the row at the end, after recording', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);

    expect(s.drafts.holdTombstone('c_work_task', 'A')).toBe(true);
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeDefined();

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');

    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();
    expect((await s.outbox.pending()).map((e) => e.columnName)).toEqual(['c_qty_installed']);
  });

  it('does not hold a tombstone for a row with no draft', async () => {
    const s = await setup();
    db = s.db;
    expect(s.drafts.holdTombstone('c_work_task', 'A')).toBe(false);
  });

  it('still deletes the row when a draft begun after the hold is the one that ends last', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    expect(s.drafts.holdTombstone('c_work_task', 'A')).toBe(true);

    // A new draft opens on the same row after the tombstone was already held.
    // Its own DraftState never gets `heldTombstone` set, so the row must not
    // rely on that flag alone to know the row is still tombstoned.
    s.drafts.begin('c_work_task', 'A', 'rowstate', 'RELEASED');

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeDefined();

    await s.drafts.end('c_work_task', 'A', 'rowstate');
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();
  });

  it('endAll commits every open draft', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 3);
    s.drafts.begin('c_work_task', 'A', 'rowstate', 'RELEASED');
    s.drafts.set('c_work_task', 'A', 'rowstate', 'WORKSTARTED');

    await s.drafts.endAll();

    expect(s.drafts.activeColumns('c_work_task', 'A').size).toBe(0);
    expect((await s.outbox.pending()).map((e) => e.columnName).sort()).toEqual(['c_qty_installed', 'rowstate']);
  });
});
