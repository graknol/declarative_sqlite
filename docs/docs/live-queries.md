---
title: Live queries
description: "SQL queries that stay current: reads, scopes, emission rules and loading state."
---

# Live queries

A live query is a SQL query that keeps its result current. You declare what
it reads; the library re-runs it after any committed write that could affect
it and tells your subscribers when the rows changed.

```ts
const query = db.live<{ system_id: string; title: string; hours: number | null }>({
  sql: 'SELECT system_id, title, hours FROM task WHERE project_id = ? ORDER BY title',
  params: [42],
  reads: [{ table: 'task', scope: { project_id: 42 } }],
  key: 'system_id',
});

const unsubscribe = query.subscribe((rows) => render(rows));

query.snapshot();   // the latest rows, synchronously
query.hasLoaded;    // false until the first run finishes
await query.refresh(); // re-run now
query.close();      // stop; call when the view goes away
```

## The spec

| Field | Meaning |
|---|---|
| `sql`, `params` | The query. Any `SELECT`, including joins |
| `reads` | Every table the query reads, each with an optional `scope` |
| `key` | The column that identifies a row across results, usually `system_id` |
| `overlayTable` | Which synced table's pending edits and drafts to apply to the rows. Defaults to the first entry in `reads` |
| `minInterval` | Minimum milliseconds between emissions. Rarely needed |

## When a query re-runs

A query re-runs after a transaction commits if that transaction wrote one of
the tables in `reads`, and:

- the entry has no `scope`, or
- a written row's scope values match the entry's `scope`, or
- the writer couldn't say which rows it touched (for example `db.execute` with
  `invalidates`).

So a query scoped to `{ project_id: 42 }` doesn't re-run when a pull writes
rows for project 7. Scopes are matched on the synced table's scope columns;
for tables without scope columns, every write to the table re-runs the query.

**List every table the query reads**, including joined ones. A table missing
from `reads` won't trigger a re-run when it changes.

Other guarantees:

- **One re-run per transaction.** A pull page of 500 rows is one transaction,
  so it causes one re-run, not 500.
- **Emit only on change.** If the new result has the same rows with the same
  values in the same order, subscribers aren't called.
- **Stable row objects.** Rows that didn't change keep the same object, so a
  React list keyed by id, or a `memo` component, skips them.
- **Nothing half-done.** Writes that roll back never reach a live query.

## Loading versus empty

`snapshot()` is `[]` both before the first run and after a first run that
found nothing. Use `hasLoaded` to tell them apart:

```ts
if (!query.hasLoaded) showSpinner();
else if (query.snapshot().length === 0) showEmptyState();
else render(query.snapshot());
```

A subscriber that joins after the first run is called straight away with the
current rows, even when they're empty.

## Synced tables: what you see

When a sync runtime is running, rows from a synced table pass through two
steps before a live query emits them:

1. **Outbox overlay.** A column with an unconfirmed edit shows the edited
   value, even if a pull has written a newer server value in the meantime.
2. **Draft hold.** A column the user is typing in shows the draft value.

The overlay and hold apply to the table named by `overlayTable` (or the first
`reads` entry). In a query that joins two synced tables, only that one table's
columns get them.

## Closing queries

Always close queries you no longer need. `db.close()` closes any that are
still open. In React, `useLiveQuery` does this for you.
