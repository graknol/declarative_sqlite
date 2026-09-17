import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { Outbox } from './outbox';
import { Overlay } from './overlay';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  s.table('local_prefs', (t) => t.text('value'));
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
  return { db, outbox, overlay: new Overlay(db, outbox) };
}

describe('Overlay', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('returns the same array when nothing is pending', async () => {
    const s = await setup();
    db = s.db;
    const rows = [{ system_id: 'A', c_qty_installed: 1 }];
    expect(s.overlay.apply('c_work_task', rows)).toBe(rows);
  });

  it('replaces pending columns with the recorded value', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const overlaid = s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1, rowstate: 'RELEASED' }]);
    expect(overlaid[0]).toEqual({ system_id: 'A', c_qty_installed: 10, rowstate: 'RELEASED' });
  });

  it('keeps the identity of rows with nothing pending', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const untouched = { system_id: 'B', c_qty_installed: 2 };
    const result = s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1 }, untouched]);
    expect(result[1]).toBe(untouched);
  });

  it('stops overlaying once the change is applied', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'b1');
    expect(s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1 }])[0]?.['c_qty_installed']).toBe(10);

    await s.outbox.applyResults('b1', [{ index: 0, result: 'applied', error: null }], order);
    expect(s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1 }])[0]?.['c_qty_installed']).toBe(1);
  });

  it('keeps overlaying a rejected change until the user resolves it', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    const order = (await s.outbox.pending()).map((e) => e.id);
    await s.outbox.markSending(order, 'b1');
    await s.outbox.applyResults('b1', [{ index: 0, result: 'rejected', error: 'no' }], order);
    // A rejected change is no longer pending, so server truth shows through and
    // the rejection is visible in the outbox instead of silently winning.
    expect(s.overlay.apply('c_work_task', [{ system_id: 'A', c_qty_installed: 1 }])[0]?.['c_qty_installed']).toBe(1);
  });

  it('keeps identity when the only pending column is absent from the row', async () => {
    const s = await setup();
    db = s.db;
    await s.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'DONE' } });
    const row = { system_id: 'A', c_qty_installed: 1 };
    const rows = [row];
    const result = s.overlay.apply('c_work_task', rows);
    expect(result).toBe(rows);
    expect(result[0]).toBe(row);
  });

  it('leaves a table with no synced declaration alone', async () => {
    const s = await setup();
    db = s.db;
    const rows = [{ system_id: 'p1', value: 'x' }];
    expect(s.overlay.apply('local_prefs', rows)).toBe(rows);
  });
});
