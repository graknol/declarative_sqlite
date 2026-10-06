# Changelog

## Unreleased (next 3.0.x patch)

### Fixed
- A pull page fetched before a push but applied after the push answer no
  longer rolls the row back. `PullApplier.applyPage` now skips a row whose
  `seq` is strictly below the local `sync_seq` (new `staleGuard` option,
  default on; counted in `skippedBySeq`). Equal seqs are still written, so
  the rewind window behaves as before. The applier also remembers the seq of
  recent tombstones, so a stale page cannot bring back a row a newer deletion
  removed. A `from: 0` pull turns the guard off (`staleGuard: false`), so a
  full re-read can still repair a device after the server's sequence
  restarted. Push answers keep their stricter `seq <= local` guard.

### Added
- `OpfsAdapter` pool sizing and cleanup, for devices several users sign in
  to. The SAH pool keeps each database in one of a fixed number of slots
  (sqlite-wasm's default is 6) under random file names, so a database could
  not be deleted from outside and every user who ever signed in kept a slot
  until opens failed with "SAH pool is full".
  - Options `initialCapacity` (slots when the pool is first created) and
    `minimumCapacity` (the pool must have at least this many, or `open()`
    fails). Also accepted by
    `openAdapter({ opfs: { poolName, initialCapacity, minimumCapacity } })`.
  - `adapter.deleteDatabase(name?)` closes the adapter first if `name` is
    its own (the default), then unlinks the database and its
    `-journal`/`-wal`/`-shm` names from the pool, freeing the slots.
    Resolves `true` if the database existed.
  - `OpfsAdapter.deleteDatabase(name, options?)` does the same without an
    open adapter.
  - `adapter.poolInfo()` returns `{ capacity, fileCount, fileNames }`.
  - Call both deletes from the context (tab or worker) that owns the
    databases: the pool allows one holder per origin. Both throw if the
    database is open through another `OpfsAdapter` in that context.
  - If another context holds the pool, the static delete rejects with an
    error whose `cause` is the browser's `NoModificationAllowedError`. The
    library does not delete anything itself in that case. sqlite-wasm's own
    cleanup of the failed install (`removeVfs()`, a recursive delete of the
    pool directory) runs, and only the browser's OPFS locks on the other
    context's files stop it. Checked in Chromium (`browser-test/`). The
    failure is cached per context, so the static delete does not retry it.
  - When the static delete had to install or resume the pool and nothing is
    open through it afterwards, it pauses the pool again (`pauseVfs`,
    sqlite-wasm 3.50+), so the context that owns the databases can still
    open it. `open()` resumes a paused pool. With sqlite-wasm older than
    3.50 (the dependency range still starts at 3.47.2) there is no pause, and
    the pool stays held by the context that installed it until that context
    ends.
- `npm run test:browser`: Playwright (Chromium) tests of the OPFS adapter on
  real OPFS, outside `npm test`.

### Fixed
- `OpfsAdapter.open()` tries to leave room for one more database and its
  journal: it grows the pool to `fileCount + 2` slots. That is best effort:
  if OPFS refuses (quota), it warns and still opens an existing database.
  Defaults are otherwise unchanged (pool `declarative-sqlite`, initial
  capacity 6).
- `OpfsAdapter.open()` no longer calls `pool.removeVfs()` when the database
  cannot be created (e.g. a full pool). `removeVfs()` deletes the pool's
  whole directory, so that failure deleted every other database in the pool.
  The pool is paused instead where sqlite-wasm supports it, and otherwise
  stays installed.
- `open()` installs the pool with `forceReinitIfPreviouslyFailed`, so an
  open that failed because another context held the pool can be retried in
  the same context instead of replaying the first rejection.
- The Node loader also finds sqlite-wasm 3.51+'s `dist/node.mjs`. The test
  suite passes on 3.47.2, 3.50.4 and 3.53.4.
- The `OpfsAdapter` docs no longer claim it works on the main thread.
  Browsers expose `createSyncAccessHandle` only in dedicated workers.

- Outbox entries caught `sending` by a reload, crash or OS kill are no longer
  stuck forever. `createSyncRuntime` now recovers them on startup, and every
  push waits for that recovery. Each batch that was sent without an answer
  (entries still `sending`, or reset to `pending` by a network error whose
  in-memory retry died with the process) is rebuilt from the persisted
  `batch_id` in its original order and re-sent under the SAME batch id before
  any new batch, so the server's idempotent `batchId` path dedupes it. A push
  is scheduled on startup when anything was recovered. `sending` rows without
  a batch id go back to `pending`. No schema change: `outbox.batch_id` has
  been persisted since 3.0.0. New: `PushService.recover()` and
  `Outbox.recoverInFlight()`. Assumes one sync runtime per database (there is
  no cross-tab lock).

## 3.0.0

Stable release. No code changes since `3.0.0-alpha.2` — see that entry and
`3.0.0-alpha.1` below for everything v3 brought over v2, and
[`MIGRATION-v2-to-v3.md`](./MIGRATION-v2-to-v3.md) for the upgrade path.

## 3.0.0-alpha.2

### Added
- `useLiveQueryState(spec)`: alongside `useLiveQuery(spec)`, exposes
  `hasLoaded` so a list view can tell "genuinely empty" apart from "hasn't
  loaded yet" without a permanent spinner or a premature "no items". Shares
  its query machinery with `useLiveQuery` via a new internal
  `useLiveQuerySubscribe()` helper.
- `createSyncRuntime`'s `retentionDays` option (default 30, `0` disables):
  purges settled outbox entries on startup so a long-lived offline device
  doesn't accumulate one outbox row per changed column forever.

### Fixed
- A live query's first run finding zero rows now still emits and replays to
  late subscribers, instead of being silently treated as "unchanged" and
  never notifying anyone.
- `LiveRegistry`'s background `refresh()` calls (create, `setRowTransform`,
  invalidation) no longer throw unhandled `Database is closed` rejections
  when they race `Database.close()`.
- A real Vite/Rollup production build of a consuming app no longer hard-fails
  on `createRequire is not exported by __vite-browser-external` - the
  Node-only `memory-adapter` loader now reaches its `node:` builtins through
  a dynamic, default-import-only chunk a bundler can externalize instead of
  statically resolving.
- Outbox bookkeeping (`record`/`discard`/`retry`/`applyResults`) now runs
  only after a transaction's real `COMMIT`, via a new `Transaction.onCommit()`
  hook - previously a nested `Database.transaction()` call (e.g. from
  `Drafts.endRow`) could have its outbox index mutation survive a later
  rollback of the same outer transaction, leaving the index permanently
  wrong until a reload.
- `TickCoalescer` no longer lets a narrower scoped tick silently overwrite a
  pending table-wide tick (or vice versa) - the broader "everything on this
  table changed" signal now always wins regardless of arrival order.
- `Drafts.apply()` no longer marks a row - and the containing array - as
  reallocated (and its reference identity broken) even when every drafted
  column actually failed to apply, matching `Overlay.apply()`'s existing
  contract and reference-identity guarantee.
- Migration guide's Section 7 legacy-v2-detection sample corrected: it asked
  for a `Database` instance before `Database.open()` could produce one; now
  probes with the raw adapter directly before opening the v3 schema.

## 3.0.0-alpha.1

A full rewrite. v3 is a sync data layer, not a database wrapper: the three owners
of state — server truth in tables, the outbox of unconfirmed changes, and the
draft being typed — are primitives the API enforces.

### Added
- `.synced()` tables: server truth, writable only by the pull applier and the
  outbox committer through a capability object.
- `Outbox` with change groups, statuses, idempotent batch ids, retry and discard.
- `Overlay`: pending outbox columns win on every read of a synced table.
- `Drafts`: focus lifecycle, per-column holds, held tombstones, and every exit
  path (blur, Enter, save, Sync, route change, `pagehide`).
- `CursorStore`, `PullApplier`, `PullService` (window rule), `PushService`
  (debounce, groups intact, backoff, answers as receipts), `TickCoalescer`.
- `db.live(...)`: scope-aware invalidation, one emission per transaction,
  emit-on-change with row identity preserved.
- `declarative-sqlite/react`: `SyncProvider`, `useLiveQuery`, `useDraftField`,
  `useOutboxCounts`, `useSyncStatus`.
- `MemoryAdapter`, `OpfsAdapter` (SAH-pool VFS), `IndexedDbAdapter` (persisted
  image), and `openAdapter` with capability probing and an OPFS timeout.
- `FakeTransport`: a scripted server for application tests.

### Removed
- HLC, per-column LWW, `__hlc` columns, `__dirty_rows`, `bulkLoad`'s merge and
  `forceOverwrite`. The server decides; the client records and overlays.
- RxJS streams (`stream`, `subscribeToTable`) — replaced by live queries.
- File management (`files/`, ZenFS) — the app uses ZenFS directly.
- `query-builder.ts`, the persistence examples and the storage-init helpers.

### Changed
- `date()` and `guid()` store TEXT, so introspection round-trips and migrations
  stop proposing spurious table rebuilds.
- Automatic migration is still additive and still refuses to rebuild a table
  without `allowRecreate: true`.

### Known limits
- `IndexedDbAdapter` persists the whole database image after writes settle; it
  can lose the last debounce window on a crash. Prefer OPFS.
- v3 is modify-only, matching `PushBatch`: creates and deletes of server rows go
  through the app's existing v1 path until IFS defines the v3 equivalents.
