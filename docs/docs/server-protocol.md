---
title: Server protocol
description: "The exact request and response shapes a backend must implement for pull and push."
---

# Server protocol

The library never makes HTTP calls. Your `SyncTransport` does, and it must
return data in the shapes below. This page is the contract a backend (or an
adapter in front of one) has to meet.

There are two operations: **pull rows** and **push changes**.

## Naming

- Table and column names are **uppercase** on the wire (`TASK`, `PROJECT_ID`)
  and lowercase locally. The library converts in both directions.
- Row ids are strings. They're stored in the synced table's key column
  (usually `system_id`).
- Values are JSON scalars: string, number, boolean or `null`.

## Sequence numbers

The server keeps one increasing counter, the **sequence number** (`seq`).
Every time a row is created, changed or removed, it's stamped with the next
value. The client stores the highest `seq` it has seen per table and scope,
and asks for rows above it.

Sequence numbers may be handed out in a different order than transactions
commit, so a row can commit with a `seq` just below one the client has
already seen. The client handles this by re-reading the last 1000 sequence
numbers when a change notification arrives (`from: 'window'`). The server
doesn't have to do anything special for this.

## Pull rows

The library calls `transport.pullRows(request)`:

```ts
interface PullRequest {
  table: string;   // 'TASK'
  scope?: string;  // 'PROJECT_ID:42' or 'AREA:N,PROJECT_ID:42'
  after: number;   // return rows with seq > after
  limit?: number;  // page size; absent means use the server default
}
```

`scope` is a comma-separated list of `COLUMN:value` pairs: at most 4, sorted
by column name, with no commas inside values. Without `scope`, return rows
from the whole table.

Return one page:

```ts
interface RowsPage {
  table: string;     // echo of request.table
  rows: RowDoc[];    // ordered by seq ascending, at most `limit` rows
  next: number;      // the highest seq in this page, or `after` if the page is empty
  hasMore: boolean;  // true if more rows exist above `next`
}

interface RowDoc {
  id: string;                     // the row id
  seq: number;                    // the row's current sequence number
  removed: boolean;               // true if the row was deleted
  data: Record<string, unknown>;  // column values, uppercase keys; may be {} when removed
}
```

The server must:

1. Return only rows with `seq > after` that match every scope pair.
2. Order them by `seq`, and set `next` to the last one's `seq`.
3. Include **deleted rows** as `removed: true` rather than leaving them out, or
   clients will never learn they're gone.

The client keeps calling with `after = next` while `hasMore` is true (up to
100 pages per pull).

Example:

```json
{
  "table": "TASK",
  "rows": [
    { "id": "a3f1…", "seq": 1287, "removed": false,
      "data": { "PROJECT_ID": 42, "TITLE": "Install pump", "HOURS": 3 } },
    { "id": "9c02…", "seq": 1288, "removed": true, "data": {} }
  ],
  "next": 1288,
  "hasMore": false
}
```

## Push changes

The library calls `transport.push(batch)`:

```ts
interface PushBatch {
  batchId: string;   // UUID, 36 characters
  deviceId: string;  // the deviceId given to createSyncRuntime
  changes: PushChange[];  // 1 to 500
}

interface PushChange {
  table: string;      // 'TASK'
  id: string;         // row id
  column: string;     // 'HOURS'
  old: unknown;       // the value the device had before the edit (informational)
  new: unknown;       // the new value
  changedAt: string;  // ISO timestamp of the edit (informational)
}
```

Encoded as JSON, each `old` and `new` value is at most 4000 characters; the
client refuses to record anything longer.

Return:

```ts
interface PushResult {
  batchId: string;
  results: Array<{
    index: number;                            // position in batch.changes
    result: 'applied' | 'noop' | 'rejected';
    error?: string | null;                    // shown to the user when rejected
  }>;
  rows: RowDoc[];  // current state of every row the batch changed, with new seq
}
```

The server must:

1. **Apply changes in order.** When two changes target the same column, the
   last one to arrive wins, whichever device it came from. `old` is for your
   logs; don't use it to refuse a change.
2. **Answer every change.** Use `noop` if the column already had that value,
   `rejected` with an `error` if validation fails or the row doesn't exist.
   A change missing from `results` is sent again in a later batch.
3. **Be idempotent on `batchId`.** Store the answer. If the same `batchId`
   arrives again, return the stored answer without applying anything. The
   client re-sends a batch with the same id after a network error, when it
   can't know whether the first attempt went through.
4. **Bump `seq`** on every row it changes, and return those rows in `rows`.
   The client writes them locally but skips any row whose `seq` isn't newer
   than what it already has.

A change group (all columns of one `record` call) always arrives in one batch.
Applying a batch in one database transaction gives the user all-or-nothing
edits per row.

### Errors

- Throwing from `push` (network down, 5xx, timeout) means "no answer". The
  batch is retried with the same `batchId`.
- If `isTerminalError(error)` returns true for what you threw, every change in
  the batch is marked `rejected` instead. Use it for errors a retry can't fix,
  like a 400.
- Per-change failures belong in `results`, not in a thrown error.

## Change notifications (optional)

To let clients pick up other devices' changes without polling, notify them when
a table changes, carrying the table's newest `seq` and, if you can, the scope
values that changed. The app passes each message to `sync.ticks.notify`:

```ts
sync.ticks.notify({ table: 'task', seq: 1290, scopes: [42] });
```

`table` here is the **local** (lowercase) name. `scopes` is a list of values;
a scope the app has open is pulled if any of its values is in the list.

## Testing against the contract

`FakeTransport`, exported from the package, is an in-memory server that
follows this contract. Use it to test your app, and as a reference when
building the real server. See [Testing](./testing.md).
