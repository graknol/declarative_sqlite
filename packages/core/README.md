# declarative-sqlite

An offline-first sync data layer for SQLite in the browser. It is not a database
wrapper: it makes the three owners of state in an offline-first app —
**server truth** (rows pulled from your API), the **outbox** of changes you have
recorded but the server has not confirmed, and the **draft** of what a user is
typing right now — first-class, non-overlapping primitives that the API itself
enforces rather than conventions an app has to get right on its own. On top of
that it gives you a declarative schema with automatic migration, and live
queries that re-run only for the rows they actually depend on.

## Install

```bash
npm install declarative-sqlite
```

The package has two entry points:

- `declarative-sqlite` — schema, migration, adapters, `Database`, live queries,
  and the whole `sync` layer (`Outbox`, `Overlay`, `Drafts`, `createSyncRuntime`, …).
- `declarative-sqlite/react` — thin React bindings (`SyncProvider`,
  `useLiveQuery`, `useDraftField`, `useOutboxCounts`, `useSyncStatus`). `react`
  is an optional peer dependency; nothing in the root entry point needs it.

## Layering

```
schema/   fluent builder, types                        — declare tables
migration/ introspect → diff → generate → apply          — additive, automatic
adapters/ SQLiteAdapter interface: OPFS, IndexedDB, memory
db/       Database: open, query, write, transaction, invalidation bus
live/     LiveQuery: scope-aware invalidation, snapshot diffing
sync/     outbox, overlay, drafts, cursors, pull, push, ticks
react/    useLiveQuery, useDraftField, useOutboxCounts, useSyncStatus (separate entry point)
```

Dependency direction is strictly `react → sync → live → db → adapters`, with
`schema`/`migration` feeding `db`. Nothing above `db` ever executes SQL directly.

## Quick start

Declare a schema, open an adapter and a database, wire up sync, and read and
write one synced table:

```ts
import {
  SchemaBuilder,
  openAdapter,
  Database,
  createSyncRuntime,
  type SyncTransport,
} from 'declarative-sqlite';

// 1. Declare the schema. `.synced()` marks a table as server truth: `key` is
//    its server row id, `scope` is what a pull can filter by.
const schema = new SchemaBuilder();
schema
  .table('c_work_task', (t) => {
    t.real('wo_no');
    t.real('c_qty_installed');
  })
  .synced({ key: 'system_id', scope: ['wo_no'] });

// 2. Open the best storage this browser can give (OPFS, then IndexedDB, then
//    memory — see "Adapters" below), then migrate to the declared schema.
const { adapter } = await openAdapter({ name: 'apply-work.db' });
const db = await Database.open({ schema: schema.build(), adapter });

// 3. Wire up sync. `transport` is the one thing you provide — see "Sync" below.
const transport: SyncTransport = myTransport;
const sync = await createSyncRuntime({ db, transport, deviceId: 'ipad-14' });

// Pull what the server has for one work order.
await sync.pull.pull('c_work_task', { wo_no: 3188 });

// 4. Read: a live query that re-runs only for writes in its own scope.
const query = db.live<{ system_id: string; c_qty_installed: number }>({
  sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ?',
  params: [3188],
  reads: [{ table: 'c_work_task', scope: { wo_no: 3188 } }],
  key: 'system_id',
});
query.subscribe((rows) => console.log(rows));

// 5. Write: a synced table is written through the outbox, never through
//    `db.tables` (see "Writing" below).
await sync.outbox.record({
  table: 'c_work_task',
  systemId: 'A',
  changes: { c_qty_installed: 10 },
});
```

This is the shape of `src/sync/runtime.test.ts` — a real, running test in this
package — with `MemoryAdapter` swapped for `openAdapter` and a real transport.

## The three owners of state

| Owner | Where it lives | Who writes it | What a reader sees |
|---|---|---|---|
| **Server truth** | `.synced()` tables | `PullApplier` (from a pull) and the outbox committer (from `record`), both through a capability object nothing else holds | Plain rows — until overlaid |
| **Outbox** | the library's own `outbox` table | `Outbox.record` | `Overlay.apply` replaces a `pending`/`sending` column with its recorded value on every read of a synced table, so the user's own edit outlives the round trip to the server |
| **Draft** | in memory only, keyed `(table, systemId, column)` — never in a component | `Drafts.begin` / `Drafts.set`, driven by `useDraftField` | `Drafts.apply` holds a drafted column at its last emitted value, and holds a tombstone for the whole row, so a concurrent pull cannot overwrite what someone is mid-keystroke on |

A column can be server truth, outbox-pending, and drafted all at the same time;
the read path applies overlay first, then draft holds, so a reader only ever
sees the most "owned" version of a value.

## Writing

Every table falls into one of two shapes on `db.tables`:

- A plain table gets full CRUD: `db.tables.<name>.insert/update/upsert/delete/get(...)`.
- A `.synced()` table gets **only** `get`. Its `TableApi` type has no write
  methods at all — `SyncedTableApi<TRow>` only declares `get(key)` — so a
  synced table cannot be written by mistake through `db.tables`; the type
  checker refuses it and there is no cast that gets around it, because the
  write methods for that table were never generated onto the object in the
  first place.

Writes to a synced table go through `sync.outbox.record(...)` instead:

```ts
await sync.outbox.record({
  table: 'c_work_task',
  systemId: row.system_id,
  changes: { c_qty_installed: 10, rowstate: 'WORKSTARTED' },
});
```

`record` writes the local row and the outbox entries for every changed column
in one transaction — what the UI shows and what will be sent can never
disagree — and refuses a non-synced table, a row that does not exist locally,
an unknown column, an empty change set, or a change group too large to push
atomically.

## Live queries

`db.live(spec)` follows five rules:

1. **Scope-aware invalidation.** A query re-runs only when a write reports a
   row in one of its `reads` tables whose scope columns match — or when the
   writer reported no row keys at all (a full refresh), in which case every
   query on that table re-runs.
2. **One emission per transaction.** Invalidations are delivered after commit,
   coalesced, never mid-write.
3. **Emit only on change.** The new result is compared with the previous
   snapshot by `key` and by column values; an identical result emits nothing,
   and rows that did not change keep their object identity so a React
   consumer can skip re-rendering them.
4. **Overlay and holds happen inside the layer.** Before a row reaches a
   subscriber it passes through `Overlay.apply` (pending outbox values win)
   and `Drafts.apply` (held columns keep their last emitted value) —
   `createSyncRuntime` installs this automatically via `db.setRowTransform`.
   No consumer can observe raw server truth for a column the outbox or a
   draft currently owns.
5. **No debounce needed.** Per-transaction coalescing plus emit-on-change
   already bounds emissions; a `minInterval` option exists only for
   pathological writers.

```ts
const query = db.live<{ system_id: string; c_qty_installed: number }>({
  sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE wo_no = ? ORDER BY system_id',
  params: [woNo],
  reads: [{ table: 'c_work_task', scope: { wo_no: woNo } }],
  key: 'system_id',
});
const unsubscribe = query.subscribe((rows) => render(rows));
query.snapshot(); // current rows, synchronously
query.refresh();  // force a re-run
query.close();    // stop watching
```

## Sync

The library never speaks HTTP. You supply a `SyncTransport`:

```ts
import type { SyncTransport, RowsPage, PushBatch, PushResult } from 'declarative-sqlite';

const transport: SyncTransport = {
  async pullRows(req) {
    // req: { table, scope?, after, limit? } -> GET /sync/rows
    const res = await fetch(`/sync/rows?table=${req.table}&after=${req.after}` +
      (req.scope ? `&scope=${encodeURIComponent(req.scope)}` : '') +
      (req.limit ? `&limit=${req.limit}` : ''));
    return (await res.json()) as RowsPage;
  },
  async push(batch: PushBatch): Promise<PushResult> {
    const res = await fetch('/sync/push', { method: 'POST', body: JSON.stringify(batch) });
    return (await res.json()) as PushResult;
  },
};
```

`createSyncRuntime({ db, transport, deviceId })` builds everything on top of
that:

- **The window rule.** `sync.pull.pull(table, scope, { from })` starts a pull
  at the stored cursor (`from: 'cursor'`, the default), a window behind it
  (`from: 'window'`, i.e. `max(0, cursor - 1000)`, used for tick-driven pulls
  because `sync_seq` is assigned in commit order but pages can arrive out of
  order), or from zero for a manual refresh (`from: 0`). Re-seeing a row costs
  nothing — every apply is an idempotent upsert by id.
- **The push answer is a receipt, not a read.** `sync.push` debounces (2 s by
  default), batches pending outbox entries without ever splitting a change
  group, and applies the server's answer rows through the same pull-applier
  path with a seq-monotonic guard: a row whose `seq` is not above the local
  `sync_seq` is skipped. A replayed batch id returns exactly the rows as they
  were when it first ran. A network error resets the batch to `pending` and
  retries with backoff (5 s / 30 s / 2 min by default, or immediately once you
  call `sync.push.notifyOnline()`); a terminal error (`isTerminalError`) marks
  every change in the batch `rejected`, which stays visible until the user
  retries or discards it.
- **Tick coalescing.** Wire your realtime channel (e.g. SignalR) to
  `sync.ticks.notify({ table, seq, scopes? })`. Ticks collect for ~1.5 s, then
  trigger one pull per `(table, scope)` the app currently has open
  (`sync.pull.registerScope`), skipping scopes the tick's own `scopes` list
  does not mention and scopes whose cursor is already caught up.

## React

`declarative-sqlite/react` is a thin binding; all state still lives in the
library, so an unmounted component cannot lose anything.

```tsx
import type { Database, SyncRuntime } from 'declarative-sqlite';
import { SyncProvider, useLiveQuery, useDraftField, useOutboxCounts, useSyncStatus } from 'declarative-sqlite/react';

function App({ db, sync }: { db: Database; sync: SyncRuntime }) {
  return (
    <SyncProvider db={db} sync={sync} routeKey={location.pathname}>
      <WorkTaskRow systemId="A" />
    </SyncProvider>
  );
}

function WorkTaskRow({ systemId }: { systemId: string }) {
  const rows = useLiveQuery<{ system_id: string; c_qty_installed: number }>({
    sql: 'SELECT system_id, c_qty_installed FROM c_work_task WHERE system_id = ?',
    params: [systemId],
    reads: [{ table: 'c_work_task' }],
    key: 'system_id',
  });
  const qty = rows[0]?.c_qty_installed ?? 0;
  const field = useDraftField('c_work_task', systemId, 'c_qty_installed', qty);
  const outbox = useOutboxCounts();
  const status = useSyncStatus();

  return (
    <>
      <input value={field.value} onFocus={field.onFocus} onChange={field.onChange}
             onBlur={field.onBlur} onKeyDown={field.onKeyDown} />
      <span>{outbox.pending} pending, {outbox.rejected} rejected</span>
      <span>{status.online ? 'online' : `retrying (attempt ${status.attempt})`}</span>
    </>
  );
}
```

`useDraftField` is the only supported way to write an editable cell: it starts
a draft on focus, updates it on every keystroke, and ends it — sending a
changed value to the outbox, or releasing an unchanged one — on blur, Enter,
Escape (which reverts first), or one of the global exit paths `SyncProvider`
installs for you: `pagehide`, `visibilitychange` going hidden, unmount, and a
change to its `routeKey` prop. Those exits exist so backgrounding the app or
navigating away commits an in-progress edit instead of losing it, and so a
concurrent server pull can never silently overwrite a field someone is
mid-keystroke on — that column, and a tombstone for its whole row, are held at
their last known value until the draft ends.

## Adapters

`openAdapter({ name })` probes the browser and opens the best storage it can
actually get, falling back in this order:

| Browser | Backend it lands on | Behaviour across a reload |
|---|---|---|
| Chrome/Edge 108+, Firefox 111+, Safari 17+ (macOS/iPadOS) | `opfs` | Persists; the row count grows every reload |
| Safari 16 | `indexeddb` (with a warning) | Persists; the row count grows every reload |
| Private window / storage blocked | `memory` (with a "not persistent" warning) | Does not persist; the count restarts at 1 |

OPFS is opened behind a timeout (`opfsTimeoutMs`, default 5000 ms) because a
browser that reports support has been seen to hang on its first handle; the
result's `warnings` array explains any fallback so the app can log it or tell
the user their session is not durable. Pass `backend` to skip probing and fail
loudly instead of silently falling back.

**IndexedDB caveat:** `IndexedDbAdapter` persists the whole database image
after writes settle, not incrementally, so a crash can lose the last debounce
window's writes. Prefer OPFS; only fall back to IndexedDB where OPFS is
genuinely unavailable (Safari 16).

## Testing your app

Use `MemoryAdapter` for a real, in-process SQLite and `FakeTransport` as a
scripted server that behaves the way the wire format documents — rows carry a
monotonic `seq`, a push applies changes with last-arrival-wins per column, and
replaying a `batchId` returns the stored answer without re-applying it:

```ts
import { MemoryAdapter, SchemaBuilder, Database, FakeTransport, createSyncRuntime } from 'declarative-sqlite';

const schema = new SchemaBuilder();
schema.table('c_work_task', (t) => {
  t.real('wo_no');
  t.real('c_qty_installed');
}).synced({ key: 'system_id', scope: ['wo_no'] });

const db = await Database.open({ schema: schema.build(), adapter: new MemoryAdapter() });
const transport = new FakeTransport();
transport.seed('C_WORK_TASK', [{ id: 'A', data: { WO_NO: 3188, C_QTY_INSTALLED: 1 } }]);

const sync = await createSyncRuntime({ db, transport, deviceId: 'test' });
await sync.pull.pull('c_work_task', { wo_no: 3188 });

// Simulate another device editing the row, or the server rejecting a column:
transport.serverEdit('C_WORK_TASK', 'A', { C_QTY_INSTALLED: 2 });
transport.reject('C_WORK_TASK', 'C_QTY_INSTALLED', 'IFS validation failed');
transport.failNextPush(); // next push() throws, exercising retry/backoff

await db.close();
```

Because everything — the write queue, the invalidation bus, the outbox, the
draft store, the pull/push services — runs in memory against a real SQLite
engine, races you care about (a pull landing mid-keystroke, a rejected push,
a replayed batch) are ordinary `async`/`await` unit tests, not flaky
integration tests.

## Migrating from 2.x

v3 is a full rewrite: no v2 module carries over, HLC/LWW/dirty-row tracking is
gone (the server decides and logs), RxJS streams are replaced by live
queries, and file management moved out of the package entirely. See
[`MIGRATION-v2-to-v3.md`](./MIGRATION-v2-to-v3.md) for the column-by-column
mapping and a checklist for moving an existing app.
