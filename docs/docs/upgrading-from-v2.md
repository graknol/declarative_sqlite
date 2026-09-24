---
title: Upgrading from v2
description: "What changed from v2 to v3 and how to port an existing app."
---

# Upgrading from v2

v3 is a rewrite, not an incremental release. The schema builder keeps its
shape; almost everything else is new. Plan the upgrade as a port.

| v2 | v3 |
|---|---|
| `DeclarativeDatabase` | `Database.open<Rows, SyncedTables>({ schema, adapter })` |
| `AdapterFactory` | `openAdapter({ name, wasmDir })` |
| `SchemaBuilder` | Same fluent API. Drop `.lww()`, add `.synced({ key, scope })` to server tables |
| `.lww()`, `__hlc` columns, `Hlc` | Gone. The server decides: last change to arrive wins |
| `dirtyRowStore` | The built-in `outbox` table |
| `db.update(...)` on a server table | `sync.outbox.record({ table, systemId, changes })` |
| `db.stream(...)`, RxJS streams | `db.live(spec)` / `useLiveQuery(spec)` |
| `bulkLoad(...)` | `sync.pull.pull(table, scope)` |
| Push / debounced sync | Automatic after `record`; `sync.push.pushNow()` to force |
| Realtime change handler | `sync.ticks.notify({ table, seq, scopes })` |
| File management (`fileset`) | Removed from the package |

## Steps

1. Update the schema: remove `.lww()`, mark server-owned tables `.synced()`,
   and give every `notNull` column a default.
2. Replace database setup with `openAdapter` + `Database.open` +
   `createSyncRuntime`.
3. Write a `SyncTransport` for your API ([Server protocol](./server-protocol.md)).
   The server must provide sequence numbers and batch idempotency.
4. Replace writes to synced tables with `sync.outbox.record`. The type checker
   will point at every call site: synced tables have no write methods on
   `db.tables`.
5. Replace streams with live queries, and form inputs with `useDraftField`.

## Existing data

v3 uses its own tables (`outbox`, `sync_cursor`) and the `sync_seq` column. The
simplest safe upgrade is a fresh database file under a new name, filled by a
full pull. Before switching, push any unsent v2 changes, or they'll be lost.

## Not in v3

- Creating or deleting server rows from the client. The push format carries
  column changes to existing rows only.
- File storage.
- Client-side conflict resolution (HLC / LWW).

The full, app-specific migration notes are in
[MIGRATION-v2-to-v3.md](https://github.com/graknol/declarative_sqlite/blob/main/packages/core/MIGRATION-v2-to-v3.md).
