import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { createServerWriteCapability, serverWriter } from '../db/server-truth';
import { FakeTransport } from '../testing/fake-transport';
import { Outbox } from './outbox';
import { Drafts } from './drafts';
import { CursorStore } from './cursor-store';
import { PullApplier } from './pull-applier';
import { PullService } from './pull-service';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

async function setup(pageSize = 2) {
  const db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
  const writer = serverWriter(db, createServerWriteCapability());
  const outbox = new Outbox(db, writer);
  await outbox.load();
  const drafts = new Drafts(db, outbox, writer);
  const cursors = new CursorStore(db);
  const applier = new PullApplier(db, writer, outbox, drafts, cursors);
  const transport = new FakeTransport({ pageSize });
  const pull = new PullService(transport, applier, cursors, { window: 1000 });
  return { db, transport, cursors, pull };
}

describe('PullService', () => {
  let db: Database | undefined;

  afterEach(async () => {
    await db?.close();
    db = undefined;
  });

  it('follows hasMore until the scope is exhausted', async () => {
    const s = await setup(2);
    db = s.db;
    s.transport.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188 } }, { id: 'B', data: { WO_NO: 3188 } }, { id: 'C', data: { WO_NO: 3188 } },
    ]);

    const report = await s.pull.pull('c_work_task', { wo_no: 3188 });
    expect(report).toMatchObject({ rows: 3, pages: 2 });
    expect(await db.query('SELECT system_id FROM c_work_task')).toHaveLength(3);
  });

  it('sends the wire table name and the formatted scope', async () => {
    const s = await setup();
    db = s.db;
    s.transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188 } }]);
    await s.pull.pull('c_work_task', { wo_no: 3188 });
    expect(s.transport.pulls[0]).toMatchObject({ table: 'C_WORK_TASK', scope: 'WO_NO:3188', after: 0 });
  });

  it('continues from the cursor on the next pull', async () => {
    const s = await setup();
    db = s.db;
    s.transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188 } }]);
    await s.pull.pull('c_work_task', { wo_no: 3188 });
    const cursor = await s.cursors.get('c_work_task', { wo_no: 3188 });

    await s.pull.pull('c_work_task', { wo_no: 3188 });
    expect(s.transport.pulls[1]?.after).toBe(cursor);
  });

  it('rewinds by the window for a tick-driven pull', async () => {
    const s = await setup();
    db = s.db;
    await s.cursors.set('c_work_task', { wo_no: 3188 }, 5000);
    await s.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(s.transport.pulls[0]?.after).toBe(4000);
  });

  it('never rewinds below zero', async () => {
    const s = await setup();
    db = s.db;
    await s.cursors.set('c_work_task', { wo_no: 3188 }, 10);
    await s.pull.pull('c_work_task', { wo_no: 3188 }, { from: 'window' });
    expect(s.transport.pulls[0]?.after).toBe(0);
  });

  it('reads the scope whole for a manual refresh', async () => {
    const s = await setup();
    db = s.db;
    await s.cursors.set('c_work_task', { wo_no: 3188 }, 5000);
    await s.pull.pull('c_work_task', { wo_no: 3188 }, { from: 0 });
    expect(s.transport.pulls[0]?.after).toBe(0);
  });

  it('tracks the scopes the app has open', async () => {
    const s = await setup();
    db = s.db;
    const close = s.pull.registerScope('c_work_task', { wo_no: 3188 });
    s.pull.registerScope('c_work_task', { wo_no: 4000 });
    expect(s.pull.openScopes('c_work_task')).toHaveLength(2);
    close();
    expect(s.pull.openScopes('c_work_task')).toEqual([{ wo_no: 4000 }]);
  });

  it('stops after maxPages so a runaway server cannot loop forever', async () => {
    const s = await setup(1);
    db = s.db;
    s.transport.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188 } }, { id: 'B', data: { WO_NO: 3188 } }, { id: 'C', data: { WO_NO: 3188 } },
    ]);
    const report = await s.pull.pull('c_work_task', { wo_no: 3188 }, { maxPages: 2 });
    expect(report.pages).toBe(2);
    expect(report.rows).toBe(2);
  });
});
