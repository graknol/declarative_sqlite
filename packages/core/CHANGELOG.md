# Changelog

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
