import { describe, it, expect, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { SchemaBuilder } from '../schema/schema-builder';
import { Database } from '../db/database';
import { FakeTransport } from '../testing/fake-transport';
import { createSyncRuntime, type SyncRuntime } from './runtime';
import type { PushBatch, PushResult } from './wire';

function testSchema() {
  const s = new SchemaBuilder();
  s.table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
    t.text('rowstate');
  }).synced({ key: 'system_id', scope: ['wo_no'] });
  return s.build();
}

/**
 * The server outlives the app. `hangAfterApply` makes the next push reach the
 * server (it applies and stores its answer) and then never answer the device;
 * `hangBeforeApply` loses the request on the way. Both leave the client's
 * entries `sending`, the way a reload or an iOS kill mid-push does.
 */
class InterruptibleTransport extends FakeTransport {
  private hang: 'before' | 'after' | undefined;

  hangAfterApply(): void {
    this.hang = 'after';
  }

  hangBeforeApply(): void {
    this.hang = 'before';
  }

  override async push(batch: PushBatch): Promise<PushResult> {
    const hang = this.hang;
    this.hang = undefined;
    if (hang === 'before') {
      this.pushes.push(batch);
      return new Promise<PushResult>(() => undefined);
    }
    const answer = await super.push(batch);
    if (hang === 'after') return new Promise<PushResult>(() => undefined);
    return answer;
  }
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

async function seedRows(db: Database, transport: FakeTransport, runtime: SyncRuntime) {
  transport.seed('C_WORK_TASK', [
    { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } },
    { id: 'B', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } },
  ]);
  await runtime.pull.pull('c_work_task', { wo_no: 3188 });
  expect(await db.query('SELECT system_id FROM c_work_task')).toHaveLength(2);
}

/** Starts the runtime the way an app does after a reload: new objects, same database, same server. */
function restart(db: Database, transport: FakeTransport): Promise<SyncRuntime> {
  return createSyncRuntime({ db, transport, deviceId: 'ipad', debounceMs: 60_000 });
}

async function serverSeq(transport: FakeTransport, id: string): Promise<number | undefined> {
  const page = await transport.pullRows({ table: 'C_WORK_TASK', after: 0 });
  return page.rows.find((row) => row.id === id)?.seq;
}

type OutboxRow = { id: string; status: string; batch_id: string | null; error_text: string | null; applied_at: string | null };

function outboxRows(db: Database): Promise<OutboxRow[]> {
  return db.query<OutboxRow>('SELECT id, status, batch_id, error_text, applied_at FROM outbox ORDER BY changed_at, rowid');
}

describe('Outbox recovery after a restart mid-push', () => {
  let db: Database | undefined;
  let runtime: SyncRuntime | undefined;

  afterEach(async () => {
    runtime?.close();
    runtime = undefined;
    await db?.close();
    db = undefined;
  });

  it('re-sends entries left sending under their original batch id and settles them', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new InterruptibleTransport();
    runtime = await restart(db, transport);
    await seedRows(db, transport, runtime);

    await runtime.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'WORKSTARTED', c_qty_installed: 10 } });
    await runtime.outbox.record({ table: 'c_work_task', systemId: 'B', changes: { c_qty_installed: 20 } });
    transport.hangBeforeApply();
    void runtime.push.pushNow();
    await settle();

    const firstBatch = transport.pushes[0]!;
    expect((await runtime.outbox.counts()).sending).toBe(3);
    runtime.close(); // the app is killed; the push never answers

    runtime = await restart(db, transport);
    // Still overlaid after the restart: the user's value, not the server's.
    expect(runtime.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 10 });

    const outcome = await runtime.push.pushNow();
    const resent = transport.pushes[1]!;
    expect(resent.batchId).toBe(firstBatch.batchId);
    expect(resent.changes).toEqual(firstBatch.changes);
    expect(outcome).toMatchObject({ applied: 3, batches: 1 });
    expect((await outboxRows(db)).map((r) => r.status)).toEqual(['applied', 'applied', 'applied']);
    expect(runtime.outbox.hasPending('c_work_task', 'A')).toBe(false);
    expect(await db.queryOne('SELECT c_qty_installed, rowstate FROM c_work_task WHERE system_id = ?', ['A'])).toEqual({
      c_qty_installed: 10,
      rowstate: 'WORKSTARTED',
    });
  });

  it("takes the server's stored answer for a batch it already applied, without applying it twice", async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new InterruptibleTransport();
    runtime = await restart(db, transport);
    await seedRows(db, transport, runtime);

    await runtime.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    transport.hangAfterApply();
    void runtime.push.pushNow();
    await settle();
    const seqAfterFirstApply = await serverSeq(transport, 'A');
    runtime.close();

    runtime = await restart(db, transport);
    const outcome = await runtime.push.pushNow();

    const firstId = transport.pushes[0]!.batchId;
    expect(transport.pushes.map((p) => p.batchId)).toEqual([firstId, firstId]);
    // The stored answer says `applied`. Under a new batch id the server would
    // have evaluated the change again (here: `noop`); it did not.
    expect(outcome).toMatchObject({ applied: 1, noop: 0 });
    expect(await serverSeq(transport, 'A')).toBe(seqAfterFirstApply);
    expect((await outboxRows(db)).map((r) => r.status)).toEqual(['applied']);
  });

  it('re-sends under the original id after a network error followed by a restart', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new InterruptibleTransport();
    runtime = await restart(db, transport);
    await seedRows(db, transport, runtime);

    await runtime.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    transport.failNextPush();
    await runtime.push.pushNow();
    const [row] = await outboxRows(db);
    expect(row).toMatchObject({ status: 'pending', batch_id: transport.pushes[0]!.batchId });
    runtime.close(); // the in-memory retry batch dies with the process

    runtime = await restart(db, transport);
    await runtime.push.pushNow();
    expect(transport.pushes[1]!.batchId).toBe(transport.pushes[0]!.batchId);
    expect((await outboxRows(db)).map((r) => r.status)).toEqual(['applied']);
  });

  it('returns legacy sending rows without a batch id to pending and sends them', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new InterruptibleTransport();
    runtime = await restart(db, transport);
    await seedRows(db, transport, runtime);

    await runtime.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    await db.execute(`UPDATE outbox SET status = 'sending', batch_id = NULL`);
    runtime.close();

    runtime = await restart(db, transport);
    expect(await outboxRows(db)).toEqual([expect.objectContaining({ status: 'pending', batch_id: null })]);
    await runtime.push.pushNow();
    expect(transport.pushes).toHaveLength(1);
    expect((await outboxRows(db)).map((r) => r.status)).toEqual(['applied']);
  });

  it('leaves pending, settled and rejected rows alone, and sends the recovered batch first', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new InterruptibleTransport();
    runtime = await restart(db, transport);
    await seedRows(db, transport, runtime);

    transport.reject('C_WORK_TASK', 'ROWSTATE', 'WTCERR2: not allowed');
    await runtime.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 5 } });
    await runtime.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { rowstate: 'WORKSTARTED' } });
    await runtime.push.pushNow(); // one applied, one rejected
    await runtime.outbox.record({ table: 'c_work_task', systemId: 'B', changes: { c_qty_installed: 1 } });
    await runtime.push.pushNow(); // noop
    await runtime.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    transport.hangBeforeApply();
    void runtime.push.pushNow(); // left sending
    await settle();
    await runtime.outbox.record({ table: 'c_work_task', systemId: 'B', changes: { c_qty_installed: 30 } }); // plain pending
    const interrupted = transport.pushes.at(-1)!;
    runtime.close();

    const before = await outboxRows(db);
    expect(before.map((r) => r.status)).toEqual(['applied', 'rejected', 'noop', 'sending', 'pending']);

    runtime = await restart(db, transport);
    expect(await outboxRows(db)).toEqual(before);

    const pushesBefore = transport.pushes.length;
    await runtime.push.pushNow();
    const sent = transport.pushes.slice(pushesBefore);
    expect(sent[0]!.batchId).toBe(interrupted.batchId);
    expect(sent[1]!.batchId).not.toBe(interrupted.batchId);
    expect(sent.map((p) => p.changes.map((c) => c.new))).toEqual([[10], [30]]);

    const after = await outboxRows(db);
    expect(after.slice(0, 3)).toEqual(before.slice(0, 3));
    expect(after.slice(3).map((r) => r.status)).toEqual(['applied', 'applied']);
  });

  it('schedules a push on startup when something was recovered', async () => {
    db = await Database.open({ schema: testSchema(), adapter: new MemoryAdapter() });
    const transport = new InterruptibleTransport();
    runtime = await restart(db, transport);
    await seedRows(db, transport, runtime);
    await runtime.outbox.record({ table: 'c_work_task', systemId: 'A', changes: { c_qty_installed: 10 } });
    transport.hangBeforeApply();
    void runtime.push.pushNow();
    await settle();
    runtime.close();

    runtime = await createSyncRuntime({ db, transport, deviceId: 'ipad', debounceMs: 0 });
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(transport.pushes).toHaveLength(2);
    expect((await outboxRows(db)).map((r) => r.status)).toEqual(['applied']);
  });
});

/**
 * The exact DDL 3.0.32 creates for this schema, dumped from the published
 * package (`sqlite_master` after `Database.open`). `outbox.batch_id` already
 * exists there, so no migration is needed; this proves an existing device
 * database opens unchanged and its interrupted push is recovered.
 */
const DDL_3_0_32 = [
  `CREATE TABLE "c_work_task" (
  "system_id" TEXT NOT NULL DEFAULT '',
  "system_removed" INTEGER NOT NULL DEFAULT 0,
  "sync_seq" INTEGER NOT NULL DEFAULT 0,
  "wo_no" REAL,
  "c_qty_installed" REAL,
  "rowstate" TEXT,
  PRIMARY KEY ("system_id")
)`,
  `CREATE TABLE "outbox" (
  "id" TEXT NOT NULL DEFAULT '',
  "table_name" TEXT NOT NULL DEFAULT '',
  "system_id" TEXT NOT NULL DEFAULT '',
  "column_name" TEXT NOT NULL DEFAULT '',
  "old_value" TEXT,
  "new_value" TEXT,
  "changed_at" TEXT NOT NULL DEFAULT '',
  "status" TEXT NOT NULL DEFAULT 'pending',
  "group_id" TEXT NOT NULL DEFAULT '',
  "batch_id" TEXT,
  "error_text" TEXT,
  "applied_at" TEXT,
  PRIMARY KEY ("id")
)`,
  `CREATE INDEX "idx_outbox_status_changed_at" ON "outbox" ("status", "changed_at")`,
  `CREATE INDEX "idx_outbox_table_name_system_id_status" ON "outbox" ("table_name", "system_id", "status")`,
  `CREATE TABLE "sync_cursor" (
  "scope_key" TEXT NOT NULL DEFAULT '',
  "table_name" TEXT NOT NULL DEFAULT '',
  "scope" TEXT,
  "last_sync_seq" INTEGER NOT NULL DEFAULT 0,
  "synced_at" TEXT NOT NULL DEFAULT '',
  PRIMARY KEY ("scope_key")
)`,
];

describe('Outbox recovery on a database created by 3.0.32', () => {
  let db: Database | undefined;
  let runtime: SyncRuntime | undefined;

  afterEach(async () => {
    runtime?.close();
    runtime = undefined;
    await db?.close();
    db = undefined;
  });

  it('opens without a migration and recovers both batched and legacy sending rows', async () => {
    const adapter = new MemoryAdapter();
    await adapter.open();
    for (const sql of DDL_3_0_32) await adapter.exec(sql);
    await adapter.run(
      `INSERT INTO c_work_task (system_id, wo_no, c_qty_installed, rowstate, sync_seq) VALUES ('A', 3188, 10, 'RELEASED', 1), ('B', 3188, 20, 'RELEASED', 2)`,
    );
    const insert = `INSERT INTO outbox (id, table_name, system_id, column_name, old_value, new_value, changed_at, status, group_id, batch_id)
                    VALUES (?, 'c_work_task', ?, 'c_qty_installed', '1', ?, ?, 'sending', ?, ?)`;
    const batchId = '11111111-1111-4111-8111-111111111111';
    await adapter.run(insert, ['e1', 'A', '10', '2026-09-27T10:00:00.000Z', 'g1', batchId]);
    await adapter.run(insert, ['e2', 'B', '20', '2026-09-27T10:00:01.000Z', 'g2', null]);

    db = await Database.open({ schema: testSchema(), adapter });
    const outboxDdl = await db.queryOne<{ sql: string }>(`SELECT sql FROM sqlite_master WHERE name = 'outbox'`);
    expect(outboxDdl?.sql).toBe(DDL_3_0_32[1]);

    const transport = new FakeTransport();
    transport.seed('C_WORK_TASK', [
      { id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } },
      { id: 'B', data: { WO_NO: 3188, C_QTY_INSTALLED: 1, ROWSTATE: 'RELEASED' } },
    ]);
    runtime = await restart(db, transport);
    expect(runtime.outbox.pendingValue('c_work_task', 'A', 'c_qty_installed')).toEqual({ value: 10 });
    expect(await outboxRows(db)).toEqual([
      expect.objectContaining({ id: 'e1', status: 'sending', batch_id: batchId }),
      expect.objectContaining({ id: 'e2', status: 'pending', batch_id: null }),
    ]);

    await runtime.push.pushNow();
    expect(transport.pushes.map((p) => p.batchId)[0]).toBe(batchId);
    expect(transport.pushes).toHaveLength(2);
    expect((await outboxRows(db)).map((r) => r.status)).toEqual(['applied', 'applied']);
  });
});
