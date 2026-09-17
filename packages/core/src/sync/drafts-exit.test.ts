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

  it('leaves the draft in place when its end() write throws', async () => {
    const s = await setup();
    db = s.db;
    const tooWide = 'x'.repeat(4001);
    s.drafts.begin('c_work_task', 'A', 'rowstate', 'RELEASED');
    s.drafts.set('c_work_task', 'A', 'rowstate', tooWide);

    await expect(s.drafts.end('c_work_task', 'A', 'rowstate')).rejects.toThrow();

    expect(s.drafts.isActive('c_work_task', 'A', 'rowstate')).toBe(true);
    expect(s.drafts.get('c_work_task', 'A', 'rowstate')).toBe(tooWide);
    expect(await db.queryOne('SELECT rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'RELEASED' });
  });

  it('endRow leaves every column of the row untouched when a later column throws', async () => {
    const s = await setup();
    db = s.db;
    const tooWide = 'x'.repeat(4001);
    // Insertion order matters: c_qty_installed is processed first and would
    // have already committed under the old per-column-transaction code by the
    // time rowstate's write throws.
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    s.drafts.begin('c_work_task', 'A', 'rowstate', 'RELEASED');
    s.drafts.set('c_work_task', 'A', 'rowstate', tooWide);

    await expect(s.drafts.endRow('c_work_task', 'A')).rejects.toThrow();

    expect(s.drafts.isActive('c_work_task', 'A', 'c_qty_installed')).toBe(true);
    expect(s.drafts.get('c_work_task', 'A', 'c_qty_installed')).toBe(12);
    expect(s.drafts.isActive('c_work_task', 'A', 'rowstate')).toBe(true);
    expect(s.drafts.get('c_work_task', 'A', 'rowstate')).toBe(tooWide);

    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 1,
      rowstate: 'RELEASED',
    });
    expect(await s.outbox.pending()).toEqual([]);
  });

  it('endRow commits every column of the row when all writes succeed', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    s.drafts.begin('c_work_task', 'A', 'rowstate', 'RELEASED');
    s.drafts.set('c_work_task', 'A', 'rowstate', 'WORKSTARTED');

    await s.drafts.endRow('c_work_task', 'A');

    expect(s.drafts.activeColumns('c_work_task', 'A').size).toBe(0);
    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 12,
      rowstate: 'WORKSTARTED',
    });
    expect((await s.outbox.pending()).map((e) => e.columnName).sort()).toEqual(['c_qty_installed', 'rowstate']);
  });

  it('does not delete a row when a new draft begins before endRow\'s transaction starts', async () => {
    const s = await setup();
    db = s.db;
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);
    s.drafts.set('c_work_task', 'A', 'c_qty_installed', 12);
    expect(s.drafts.holdTombstone('c_work_task', 'A')).toBe(true);

    // Not awaited: endRow runs synchronously up to its first `await` (opening
    // the shared transaction) and then yields control back here, before the
    // transaction body — and its tombstone-delete decision — ever runs.
    const endRowPromise = s.drafts.endRow('c_work_task', 'A');
    // Lands in that gap: a fresh draft on another column of the same row,
    // added to the very Map endRow already snapshotted a reference to.
    s.drafts.begin('c_work_task', 'A', 'rowstate', 'WORKSTARTED');

    await endRowPromise;

    // The row must survive: a new, unrelated draft is open on it.
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeDefined();
    expect(s.drafts.isActive('c_work_task', 'A', 'rowstate')).toBe(true);
    expect(s.drafts.get('c_work_task', 'A', 'rowstate')).toBe('WORKSTARTED');

    // The tombstone must have survived too, ready to apply once this last
    // draft also ends.
    await s.drafts.end('c_work_task', 'A', 'rowstate');
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();
  });
});
