---
title: For AI agents
description: "Machine-readable docs and the rules an agent must follow when writing code against declarative-sqlite."
---

# For AI agents

These docs are published in forms meant for LLMs and coding agents:

| URL | Contents |
|---|---|
| [`/llms.txt`](pathname:///llms.txt) | Index of every page, with one-line summaries and links to Markdown |
| [`/llms-full.txt`](pathname:///llms-full.txt) | Every page as a single Markdown file |
| `/docs/<page>.md` | Any single page as raw Markdown, e.g. [`/docs/sync.md`](pathname:///docs/sync.md) |

To give an agent the whole library in one go, point it at
`https://declarative-sqlite.linden.no/llms-full.txt`.

The package also ships TypeScript declarations (`dist/*.d.ts`). When these
docs and the types disagree, the types are right.

## Rules for writing code with this library

These are the mistakes that compile but break at runtime or corrupt sync
state. Follow them in generated code.

1. **Install the v3 alpha**: `npm install declarative-sqlite@alpha`. The
   untagged `latest` is v2, a different API.
2. **Never write a `.synced()` table directly.** Not with `db.tables`, and not
   with `db.execute` or `tx.execute`. Use `sync.outbox.record({ table,
   systemId, changes })`.
3. **`outbox.record` only changes existing rows.** It can't create or delete
   synced rows; those come from the server by pulling. Don't write workarounds
   that insert into synced tables.
4. **Supply `system_id` on insert** into a plain table
   (`crypto.randomUUID()`). It isn't generated.
5. **Give every `.notNull()` a default of the column's type**:
   `t.integer('n').notNull(0)`, `t.text('s').notNull('')`.
6. **Declare every table a live query reads** in `reads`, joined tables
   included, and set `key` to the row id column (usually `system_id`).
7. **Close what you open**: `query.close()` for live queries you created,
   `sync.close()` before `await db.close()`.
8. **Create one database and one sync runtime per app**, outside React
   components, and hand them to `<SyncProvider>`.
9. **Use `useDraftField` for editable inputs bound to synced columns**, not
   `useState` plus `record`. Convert numbers in `onChange`; the event value is
   a string.
10. **Use lowercase names locally, uppercase on the wire.** `sync.pull.pull('task',
    { project_id: 42 })` and `sync.ticks.notify({ table: 'task', … })` take
    local names. `FakeTransport.seed('TASK', …)` and everything a
    `SyncTransport` sends or receives use wire names.
11. **Don't declare tables named `outbox` or `sync_cursor`, or recreate the
    `system_id`, `system_removed` or `sync_seq` columns** with other types.
12. **Throw from the transport on network failure.** Don't return an empty
    result: a thrown `push` is retried with the same batch id, while an
    invented answer is filed as the server's verdict.
13. **Test with `MemoryAdapter` and `FakeTransport`**, not mocks of the
    library.

## Minimal complete example

```ts
import { SchemaBuilder, openAdapter, Database, createSyncRuntime, type SyncTransport } from 'declarative-sqlite';

interface Rows {
  task: { system_id: string; project_id: number; title: string; hours: number | null };
}

const schema = new SchemaBuilder();
schema
  .table('task', (t) => {
    t.integer('project_id').notNull(0);
    t.text('title').notNull('');
    t.real('hours');
  })
  .synced({ key: 'system_id', scope: ['project_id'] });

export async function start(transport: SyncTransport, deviceId: string) {
  const { adapter, warnings } = await openAdapter({ name: 'app.db' });
  warnings.forEach((w) => console.warn(w));

  const db = await Database.open<Rows, 'task'>({ schema: schema.build(), adapter });
  const sync = await createSyncRuntime({ db, transport, deviceId });

  await sync.pull.pull('task', { project_id: 42 });

  const tasks = db.live<Rows['task']>({
    sql: 'SELECT * FROM task WHERE project_id = ? ORDER BY title',
    params: [42],
    reads: [{ table: 'task', scope: { project_id: 42 } }],
    key: 'system_id',
  });
  tasks.subscribe((rows) => console.log(rows));

  const first = (await db.queryOne<Rows['task']>('SELECT * FROM task LIMIT 1'))!;
  await sync.outbox.record({ table: 'task', systemId: first.system_id, changes: { hours: 2 } });

  return async () => {
    tasks.close();
    sync.close();
    await db.close();
  };
}
```
