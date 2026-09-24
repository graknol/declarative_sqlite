# Changelog

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
