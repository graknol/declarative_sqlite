import { describe, it, expect, afterEach, vi } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';
import { Drafts } from './drafts';
import { CursorStore } from './cursor-store';
import { PullApplier } from './pull-applier';
import type { RowsPage } from './wire';

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
  const drafts = new Drafts(db, outbox, writer);
  const cursors = new CursorStore(db);
  const applier = new PullApplier(db, writer, outbox, drafts, cursors);
  return { db, writer, outbox, drafts, cursors, applier };
}

const page = (rows: RowsPage['rows'], next: number): RowsPage => ({ table: 'C_WORK_TASK', rows, next, hasMore: false });

describe('PullApplier', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('upserts rows, stamps sync_seq and advances the cursor', async () => {
    const s = await setup();
    db = s.db;
    const report = await s.applier.applyPage(
      'c_work_task',
      page([{ id: 'A', seq: 100, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 5, ROWSTATE: 'RELEASED' } }], 100),
      { scope: { wo_no: 3188 } },
    );

    expect(report.upserted).toBe(1);
    expect(await db.queryOne('SELECT wo_no, c_qty_installed, rowstate, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      wo_no: 3188, c_qty_installed: 5, rowstate: 'RELEASED', sync_seq: 100,
    });
    expect(await s.cursors.get('c_work_task', { wo_no: 3188 })).toBe(100);
  });

  it('commits a 200-row page as one transaction and one invalidation', async () => {
    const s = await setup();
    db = s.db;
    const listener = vi.fn();
    db.invalidations.subscribe(listener);

    const rows = Array.from({ length: 200 }, (_, i) => ({ id: `row-${i}`, seq: i + 1, removed: false, data: { WO_NO: 3188 } }));
    await s.applier.applyPage('c_work_task', page(rows, 200), { scope: { wo_no: 3188 } });

    expect(listener).toHaveBeenCalledTimes(1);
    expect(await db.query('SELECT system_id FROM c_work_task')).toHaveLength(200);
  });

  it('deletes a tombstoned row', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 1, removed: false, data: { WO_NO: 3188 } }], 1));
    const report = await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 2, removed: true, data: {} }], 2));
    expect(report.deleted).toBe(1);
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();
  });

  it('never overwrites a column with a pending outbox entry, but writes the rest of the row', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 1, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } }], 1));
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });

    const report = await s.applier.applyPage(
      'c_work_task',
      page([{ id: 'A', seq: 2, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 99, ROWSTATE: 'WORKSTARTED' } }], 2),
    );

    expect(report.keptPendingColumns).toBe(1);
    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10, rowstate: 'WORKSTARTED',
    });
  });

  it('holds a column that is being typed and applies it when the draft ends unchanged', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 1, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }], 1));
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);

    const report = await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 2, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 7 } }], 2));
    expect(report.heldColumns).toBe(1);
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 1 });

    await s.drafts.end('c_work_task', 'A', 'c_qty_installed');
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 7 });
  });

  it('holds a tombstone while the row is being typed', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 1, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }], 1));
    s.drafts.begin('c_work_task', 'A', 'c_qty_installed', 1);

    const report = await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 2, removed: true, data: {} }], 2));
    expect(report.heldTombstones).toBe(1);
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeDefined();
  });

  it('skips a row whose seq is not above the local one when the guard is on', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 10, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }], 10));

    const report = await s.applier.applyRows(
      'c_work_task',
      [{ id: 'A', seq: 10, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 42 } }],
      { seqGuard: true, advanceCursor: false },
    );

    expect(report.skippedBySeq).toBe(1);
    expect(await db.queryOne('SELECT c_qty_installed FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ c_qty_installed: 1 });
  });

  it('applies answer rows whose seq is above the local one', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 10, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }], 10));
    await s.applier.applyRows('c_work_task', [{ id: 'A', seq: 11, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 42 } }], {
      seqGuard: true, advanceCursor: false,
    });
    expect(await db.queryOne('SELECT c_qty_installed, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 42, sync_seq: 11,
    });
  });

  it('does not advance the cursor when told not to', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyRows('c_work_task', [{ id: 'A', seq: 10, removed: false, data: { WO_NO: 3188 } }], {
      scope: { wo_no: 3188 }, advanceCursor: false,
    });
    expect(await s.cursors.get('c_work_task', { wo_no: 3188 })).toBe(0);
  });
  it('a pull page answered before a push but applied after its answer does not roll the row back', async () => {
    const s = await setup();
    db = s.db;
    const scope = { wo_no: 3188 };
    const v1 = { id: 'A', seq: 100, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 5, ROWSTATE: 'ACTIVE' } };
    await s.applier.applyPage('c_work_task', page([v1], 100), { scope });

    // The push answer (the user's change, now seq 105) lands first...
    await s.applier.applyRows('c_work_task', [{ id: 'A', seq: 105, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 5, ROWSTATE: 'DELETED' } }]);
    // ...then a page the server answered before it, still carrying seq 100.
    const report = await s.applier.applyPage('c_work_task', page([v1], 100), { scope });

    expect(report.skippedBySeq).toBe(1);
    expect(await db.queryOne('SELECT rowstate, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'DELETED', sync_seq: 105 });
  });

  it('a page re-sending the same seq (the rewind window) is still written', async () => {
    const s = await setup();
    db = s.db;
    const row = { id: 'A', seq: 100, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 5, ROWSTATE: 'ACTIVE' } };
    await s.applier.applyPage('c_work_task', page([row], 100), { scope: { wo_no: 3188 } });
    const report = await s.applier.applyPage('c_work_task', page([row], 100), { scope: { wo_no: 3188 } });
    expect(report).toMatchObject({ upserted: 1, skippedBySeq: 0 });
  });

  it('a from-zero re-read (staleGuard: false) can take a lower seq, for a server whose sequence restarted', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 900, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 5, ROWSTATE: 'OLD' } }], 900), { scope: { wo_no: 3188 } });
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 7, removed: false, data: { WO_NO: 3188, C_QTY_INSTALLED: 6, ROWSTATE: 'NEW' } }], 7), { scope: { wo_no: 3188 }, staleGuard: false });
    expect(await db.queryOne('SELECT rowstate, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'NEW', sync_seq: 7 });
  });
  it('a stale tombstone does not delete a row the device holds a newer version of', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyRows('c_work_task', [{ id: 'A', seq: 105, removed: false, data: { WO_NO: 3188, ROWSTATE: 'ACTIVE' } }]);
    const report = await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 100, removed: true, data: {} }], 100));
    expect(report).toMatchObject({ skippedBySeq: 1, deleted: 0 });
    expect(await db.queryOne('SELECT rowstate, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'ACTIVE', sync_seq: 105 });
  });

  it('a stale page does not bring back a row a newer tombstone deleted', async () => {
    const s = await setup();
    db = s.db;
    const v1 = { id: 'A', seq: 100, removed: false, data: { WO_NO: 3188, ROWSTATE: 'ACTIVE' } };
    await s.applier.applyPage('c_work_task', page([v1], 100));
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 105, removed: true, data: {} }], 105));

    const stale = await s.applier.applyPage('c_work_task', page([v1], 100));
    expect(stale.skippedBySeq).toBe(1);
    expect(await db.queryOne('SELECT system_id FROM c_work_task WHERE system_id = ?', ['A'])).toBeUndefined();

    // A newer version (the row was restored on the server) is written as usual.
    await s.applier.applyPage('c_work_task', page([{ ...v1, seq: 110 }], 110));
    expect(await db.queryOne('SELECT rowstate, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'ACTIVE', sync_seq: 110 });
  });

  it('a from-zero re-read (staleGuard: false) brings back a row behind a remembered tombstone', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 900, removed: true, data: {} }], 900));
    await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 7, removed: false, data: { WO_NO: 3188, ROWSTATE: 'NEW' } }], 7), { staleGuard: false });
    expect(await db.queryOne('SELECT rowstate, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'NEW', sync_seq: 7 });
  });

  it('applies a page row over a local row that has no server seq yet', async () => {
    const s = await setup();
    db = s.db;
    await db.transaction(async (tx) => {
      await s.writer.upsert(tx, 'c_work_task', { system_id: 'A', wo_no: 3188, rowstate: 'LOCAL' });
    });
    const report = await s.applier.applyPage('c_work_task', page([{ id: 'A', seq: 3, removed: false, data: { WO_NO: 3188, ROWSTATE: 'SERVER' } }], 3));
    expect(report).toMatchObject({ upserted: 1, skippedBySeq: 0 });
    expect(await db.queryOne('SELECT rowstate, sync_seq FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({ rowstate: 'SERVER', sync_seq: 3 });
  });

  it('skips only the stale rows of a page and writes the rest', async () => {
    const s = await setup();
    db = s.db;
    await s.applier.applyRows('c_work_task', [{ id: 'B', seq: 50, removed: false, data: { WO_NO: 3188, ROWSTATE: 'PUSHED' } }]);
    const report = await s.applier.applyPage(
      'c_work_task',
      page([
        { id: 'A', seq: 10, removed: false, data: { WO_NO: 3188, ROWSTATE: 'PULLED' } },
        { id: 'B', seq: 20, removed: false, data: { WO_NO: 3188, ROWSTATE: 'OLD' } },
        { id: 'C', seq: 30, removed: false, data: { WO_NO: 3188, ROWSTATE: 'PULLED' } },
      ], 30),
      { scope: { wo_no: 3188 } },
    );
    expect(report).toMatchObject({ upserted: 2, skippedBySeq: 1 });
    expect(await db.query('SELECT system_id, rowstate FROM c_work_task ORDER BY system_id')).toEqual([
      { system_id: 'A', rowstate: 'PULLED' }, { system_id: 'B', rowstate: 'PUSHED' }, { system_id: 'C', rowstate: 'PULLED' },
    ]);
    expect(await s.cursors.get('c_work_task', { wo_no: 3188 })).toBe(30);
  });
});
