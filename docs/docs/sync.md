---
title: Sync
description: "Pull, record, push, retries, rejected changes, change notifications and runtime options."
---

# Sync

The sync runtime keeps `.synced()` tables in step with your server. It pulls
rows, records the user's edits in an outbox, pushes them, and makes sure that
neither a pull nor a push ever throws away what the user did.

```ts
import { createSyncRuntime } from 'declarative-sqlite';

const sync = await createSyncRuntime({ db, transport, deviceId });
```

Create it once, right after `Database.open`. Call `sync.close()` before
`db.close()`.

## The transport

You provide the network part as two functions. What they call is up to you;
[Server protocol](./server-protocol.md) describes what the answers must
contain.

```ts
import type { SyncTransport, RowsPage, PushResult } from 'declarative-sqlite';

// HttpError and authHeaders() stand in for your own code.

const transport: SyncTransport = {
  async pullRows(req) {
    // req = { table: 'TASK', scope?: 'PROJECT_ID:42', after: 1200, limit?: 500 }
    const params = new URLSearchParams({ table: req.table, after: String(req.after) });
    if (req.scope) params.set('scope', req.scope);
    if (req.limit) params.set('limit', String(req.limit));
    const res = await fetch(`/sync/rows?${params}`, { headers: authHeaders() });
    if (!res.ok) throw new HttpError(res.status);
    return (await res.json()) as RowsPage;
  },
  async push(batch) {
    const res = await fetch('/sync/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...authHeaders() },
      body: JSON.stringify(batch),
    });
    if (!res.ok) throw new HttpError(res.status);
    return (await res.json()) as PushResult;
  },
};
```

If `pullRows` throws, the pull rejects. If `push` throws, the batch is retried
later (see [Pushing](#pushing)).

## Pulling

```ts
const report = await sync.pull.pull('task', { project_id: 42 });
// { rows: 37, pages: 1, cursor: 1288 }
```

A pull fetches pages until the server says there are no more, and applies
each page in one transaction. The runtime stores a **cursor** per table and
scope: the highest sequence number seen so far. The next pull asks only for
rows changed after it.

`from` controls where a pull starts:

| `from` | Starts at | Use it for |
|---|---|---|
| `'cursor'` (default) | The stored cursor | Normal incremental pulls |
| `'window'` | 1000 below the cursor | Pulls triggered by a change notification (see [Ticks](#change-notifications-ticks)) |
| `0` | The beginning | A manual full refresh of that scope |

Pulling a row you already have is harmless: rows are upserted by id.

A pulled row with `removed: true` is deleted locally. Server columns your
schema doesn't declare are ignored, so the server can add columns before
clients know about them.

**A pull never overwrites the user's work:**

- A column with an unconfirmed outbox entry keeps the local value.
- A column someone is typing in is held. The server value is applied when the
  draft ends, if the user didn't change the field.
- A deletion of a row someone is typing in waits until they're done.

## Recording changes

Edits to synced rows go through the outbox:

```ts
const groupId = await sync.outbox.record({
  table: 'task',
  systemId: row.system_id,
  changes: { hours: 3.5, title: 'Install pump' },
});
```

`record` writes the new values into the local row and adds one outbox entry
per column, in a single transaction. Live queries show the new values straight
away, and a push is scheduled.

The columns in one `record` call form a **change group**: they're always sent
in the same push batch.

`record` throws `OutboxError`, and records nothing, when:

- the table isn't synced (write it through `db.tables` instead),
- the row doesn't exist locally,
- a column isn't in the schema,
- `changes` is empty, or has more than 500 columns.

It throws `ValueTooLongError` when a value encodes to more than 4000 JSON
characters.

:::info Creating and deleting rows
The outbox changes columns of rows that already exist. Creating a synced row
or deleting one isn't part of the protocol: new and removed rows come from the
server through a pull.
:::

## Pushing

Pushes happen on their own: about 2 seconds after the last `record`, pending
entries are sent in batches of up to 500 changes. A change group is never
split across two batches.

```ts
await sync.push.pushNow(); // push immediately, e.g. from a "Sync" button
```

Each outbox entry moves through these states:

| Status | Meaning |
|---|---|
| `pending` | Recorded, not sent yet |
| `sending` | In a batch waiting for an answer |
| `applied` | The server applied it |
| `noop` | The server already had that value |
| `rejected` | The server refused it; `errorText` says why |

The server's answer includes the current state of every row the batch touched,
which is written locally. An answer row older than what a pull already brought
in (a lower sequence number) is skipped.

### Network failures and retries

If `push` throws, the batch goes back to `pending` and is retried **with the
same batch id**, so a server that already applied it can just return its stored
answer. Retries wait 5 s, then 30 s, then every 2 minutes. Tell the runtime
when the connection comes back to retry at once:

```ts
window.addEventListener('online', () => sync.push.notifyOnline());
```

Some errors shouldn't be retried, such as a 400 from a malformed request. Pass
`isTerminalError`, and the whole batch is marked `rejected` instead:

```ts
const sync = await createSyncRuntime({
  db,
  transport,
  deviceId,
  isTerminalError: (error) => error instanceof HttpError && error.status >= 400 && error.status < 500,
});
```

### Rejected changes

A rejected entry stays in the outbox until the user deals with it:

```ts
sync.push.onRejected((entry) => toast(`${entry.columnName}: ${entry.errorText}`));

const rejected = await sync.outbox.entries({ status: 'rejected' });
await sync.outbox.retry(rejected[0].id);   // back to pending, sent again
await sync.outbox.discard(rejected[0].id); // drop it
```

After a rejection the local row still holds the value the user entered. It
returns to the server's value when that row is next pulled with newer data. To
fetch it now, pull the scope again with `{ from: 0 }`.

### Status

```ts
sync.push.status();
// { online: true, sending: false, attempt: 0, nextRetryAt: null, lastError: null }

const stop = sync.push.onStatusChange((status) => updateHeader(status));
const counts = await sync.outbox.counts(); // { pending, sending, rejected }
```

In React, use `useSyncStatus()` and `useOutboxCounts()`.

## Change notifications (ticks)

If your server can notify clients when a table changes (WebSockets, SignalR,
server-sent events), pass those notifications to the runtime:

```ts
socket.on('TableChanged', (msg) => {
  sync.ticks.notify({ table: 'task', seq: msg.seq, scopes: msg.projectIds });
});
```

Ticks are collected for about 1.5 seconds, then resolved together. For each
table, every scope the app currently has open is pulled once, using
`from: 'window'`. Scopes are skipped if their cursor is already at or past the
tick's `seq`, or if the tick lists `scopes` and doesn't mention them.

Tell the runtime which scopes are on screen:

```ts
const unregister = sync.pull.registerScope('task', { project_id: 42 });
// when the view closes:
unregister();
```

`sync.ticks.flush()` resolves pending ticks immediately.

## Outbox history

Settled entries (`applied`, `noop`) stay in the `outbox` table as history. On
startup the runtime deletes settled entries older than `retentionDays`
(default 30). Pass `retentionDays: 0` to turn that off and call
`sync.outbox.purgeOlderThan(days)` yourself. Rejected entries are never purged
automatically.

## Options

| Option | Default | Meaning |
|---|---|---|
| `db` | required | The open `Database` |
| `transport` | required | Your `SyncTransport` |
| `deviceId` | required | Sent with every push; use a stable id per installation |
| `debounceMs` | `2000` | Delay between the last `record` and the push |
| `maxChangesPerBatch` | `500` | Changes per push batch (500 is also the maximum) |
| `pullWindow` | `1000` | How far `from: 'window'` rewinds |
| `pageLimit` | – | Page size sent to `pullRows`. Left out, the server picks |
| `tickWindowMs` | `1500` | How long ticks are collected |
| `retentionDays` | `30` | Settled outbox history to keep |
| `isTerminalError` | every error retries | Which push errors mark a batch rejected instead of retrying |
| `clock` | `() => new Date()` | Time source, useful in tests |

## What the runtime contains

`createSyncRuntime` returns these services. Most apps only need the first
four:

| Property | Use |
|---|---|
| `pull` | `pull()`, `registerScope()` |
| `outbox` | `record()`, `entries()`, `counts()`, `retry()`, `discard()`, `purgeOlderThan()` |
| `push` | `pushNow()`, `notifyOnline()`, `status()`, `onStatusChange()`, `onRejected()` |
| `ticks` | `notify()`, `flush()` |
| `drafts` | The draft store behind `useDraftField`: `begin`, `set`, `end`, `endAll` |
| `cursors` | Read or reset stored cursors: `get`, `all`, `reset` |
| `overlay`, `applier` | Internals, exposed for advanced use and tests |
