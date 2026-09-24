---
title: Reading and writing
description: "Typed db.tables CRUD, SQL queries, transactions and raw statements."
---

# Reading and writing

## Typing the database

The library doesn't infer row types from the schema builder. Describe your
rows once and pass them to `Database.open`, together with the names of your
synced tables:

```ts
import { Database } from 'declarative-sqlite';

interface Rows {
  setting: { system_id: string; name: string; value: string | null };
  task: { system_id: string; project_id: number; title: string; hours: number | null };
}

const db = await Database.open<Rows, 'task'>({ schema: appSchema, adapter });

db.tables.setting.insert(/* … */); // full CRUD
db.tables.task.get(id);            // read-only: task is synced
```

## Queries

Reads are plain SQL with positional `?` parameters:

```ts
const tasks = await db.query<Rows['task']>(
  'SELECT * FROM task WHERE project_id = ? ORDER BY title',
  [42],
);

const one = await db.queryOne<{ n: number }>('SELECT COUNT(*) AS n FROM task');
```

Parameter values can be strings, numbers, `null` or `Uint8Array`. Rows come
back as plain objects keyed by column name.

For data that should stay on screen and update itself, use a
[live query](./live-queries.md) instead.

## db.tables

Every table in the schema has an entry in `db.tables`, keyed by its row key
(`system_id` unless the table is synced with a different key).

For tables you own (not synced):

```ts
const id = crypto.randomUUID();

await db.tables.setting.insert({ system_id: id, name: 'theme', value: 'dark' });
await db.tables.setting.update(id, { value: 'light' });   // returns rows changed
await db.tables.setting.upsert({ system_id: id, name: 'theme', value: 'dark' });
await db.tables.setting.get(id);                           // row or undefined
await db.tables.setting.delete(id);                        // returns rows changed
```

- You provide `system_id` when inserting. It isn't generated for you.
- Keys that aren't columns in the schema are ignored.
- `true` and `false` are stored as `1` and `0`; `undefined` as `NULL`.

Synced tables expose only `get`. Their write methods don't exist on the
object, so a stray `db.tables.task.update(...)` is a type error. Change synced
rows with `sync.outbox.record(...)` ([Sync](./sync.md)).

## Transactions

Group writes with `db.transaction`. Everything inside commits together or
rolls back together:

```ts
await db.transaction(async (tx) => {
  await db.tables.setting.upsert({ system_id: a, name: 'x', value: '1' });
  await db.tables.setting.upsert({ system_id: b, name: 'y', value: '2' });
  const row = await tx.queryOne('SELECT value FROM setting WHERE system_id = ?', [a]);
});
```

- Any write made while a transaction is open (through `db.tables`, `db.execute`,
  a nested `db.transaction`, or the sync layer) joins that transaction.
- Transactions run one at a time. A second caller waits for the first to
  finish.
- If the callback throws, everything rolls back and nothing is reported to
  live queries.
- `tx.onCommit(fn)` runs `fn` only after the outermost transaction really
  commits.

## Raw statements

`db.execute` runs any statement that returns no rows. Tell it which tables
you wrote, so live queries on them re-run:

```ts
await db.execute('DELETE FROM setting WHERE value IS NULL', [], { invalidates: ['setting'] });
```

Inside a transaction, use `tx.execute` the same way, and call
`tx.markWritten(table, rowKey, scope)` or `tx.markTableWritten(table)` to
report what changed.

:::warning
Never write a synced table with raw SQL. The sync layer relies on being the
only writer of those tables; writing them yourself breaks cursors and the
outbox overlay.
:::

## Closing

```ts
await db.close();
```

`close` waits for queued writes to finish, closes every live query, and then
closes the adapter. Any later call on the database throws
`DatabaseError: Database is closed`.
