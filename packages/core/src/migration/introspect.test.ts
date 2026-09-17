import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { MemoryAdapter } from '../adapters/memory-adapter';
import { introspect } from './introspect';

describe('introspect', () => {
  let adapter: MemoryAdapter;

  beforeEach(async () => {
    adapter = new MemoryAdapter();
    await adapter.open();
  });

  afterEach(async () => {
    await adapter.close();
  });

  it('returns an empty schema for an empty database', async () => {
    expect(await introspect(adapter)).toEqual({ tables: [] });
  });

  it('reads columns, types, notNull and defaults', async () => {
    await adapter.exec(`CREATE TABLE "c_work_task" (
      "system_id" TEXT NOT NULL DEFAULT '',
      "wo_no" REAL,
      "sync_seq" INTEGER NOT NULL DEFAULT 0
    )`);
    const schema = await introspect(adapter);
    expect(schema.tables).toHaveLength(1);
    expect(schema.tables[0]?.columns).toEqual([
      { name: 'system_id', type: 'TEXT', logical: 'text', notNull: true, defaultValue: '' },
      { name: 'wo_no', type: 'REAL', logical: 'real', notNull: false },
      { name: 'sync_seq', type: 'INTEGER', logical: 'integer', notNull: true, defaultValue: 0 },
    ]);
  });

  it('reads the primary key and named indexes', async () => {
    await adapter.exec(`CREATE TABLE "outbox" ("id" TEXT NOT NULL, "status" TEXT, "changed_at" TEXT, PRIMARY KEY ("id"))`);
    await adapter.exec(`CREATE INDEX "idx_outbox_status_changed_at" ON "outbox" ("status", "changed_at")`);
    const table = (await introspect(adapter)).tables[0];
    expect(table?.keys).toEqual([
      { columns: ['id'], type: 'PRIMARY' },
      { columns: ['status', 'changed_at'], type: 'INDEX', name: 'idx_outbox_status_changed_at' },
    ]);
  });

  it('ignores sqlite internal tables', async () => {
    await adapter.exec(`CREATE TABLE "t" ("id" INTEGER PRIMARY KEY AUTOINCREMENT)`);
    await adapter.run(`INSERT INTO "t" DEFAULT VALUES`);
    expect((await introspect(adapter)).tables.map((t) => t.name)).toEqual(['t']);
  });
});
