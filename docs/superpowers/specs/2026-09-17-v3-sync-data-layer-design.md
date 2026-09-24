# declarative-sqlite v3 — the sync data layer

Status: draft for owner review, 2026-09-17. Package `packages/core` (`declarative-sqlite`), major bump to 3.0.0.
Consumer: Apply Work (`work-apply-no`), Phase 3 of "Sync v3 without HLC" (spec on the owner's Desktop,
`PLAN - Sync v3 without HLC.md`, Part A and the Phase 3 framing).

## 1. Why a v3

v2 was built around conflict-free merging in the client: HLC timestamps, LWW per column, dirty rows,
merging bulk loads. Sync v3 moves all of that to the server (one integer cursor, arrival-order apply, a
server-side log). What the client needs instead is much smaller and much stricter: server truth in
tables, an outbox of unconfirmed changes, a draft layer for what is being typed, and live queries that
do not storm. The architecture is only as solid as the framework that enforces it, so these are
first-class primitives of the library, not conventions in the app.

## 2. Goals and non-goals

Goals
- Preserve the behaviour that earned its place, reimplemented cleanly: fluent declarative schema and
  **automatic migration** (introspect → diff → generate → apply; add-only, never drops data
  automatically), and the SQLite WASM adapters (OPFS, IndexedDB, memory).
- Make the three owners of state explicit and non-overlapping: **server truth** (tables), **outbox**
  (recorded, unconfirmed), **draft** (being typed).
- Live queries that re-run only for rows in their scope, emit once per write transaction, and only
  when the result actually changed.
- Everything runs in memory so every race we know of is a unit test.
- Transport-agnostic: the library does not know HTTP. The app supplies a `SyncTransport`.

Non-goals
- Client-side conflict resolution. The server decides (last arrival wins per column) and logs.
- File/blob storage (v2 `files/`): dropped from core; the app uses ZenFS directly.
- The Dart/Flutter packages: unchanged.

## 3. A full rewrite, with v2 as reference only

Owner decision (2026-09-17): v3 is written from scratch in `packages/core` with the skills and
process we have now (design → plan → TDD with in-memory tests → review). No v2 module is carried
over; v2 code is read for behaviour and edge cases, not copied. What is preserved is **behaviour**:

| v2 behaviour | v3 |
|---|---|
| Fluent declarative schema (`schema.table(...).text()/real()/integer()/notNull()/primary()`) | reimplemented; same shape so `schema.ts` survives minus `.lww()`, plus `.synced()` |
| Automatic migration: introspect `sqlite_master` → diff → generate → apply, additive, plan mode, guarded recreation | reimplemented with a full test matrix (section 9) |
| SQLite WASM adapters: OPFS, IndexedDB, memory; Safari fallback | reimplemented over the official `@sqlite.org/sqlite-wasm` build; one adapter interface |
| Typed CRUD per table | reimplemented as `db.tables.<name>` generated from the schema |
| HLC / LWW / dirty rows / merging bulk load / `forceOverwrite` | gone (server decides, see Sync v3 Part A) |
| RxJS streams refreshed on table name | gone; replaced by `live/` (section 6) |
| File management (`files/`) | gone from core; the app uses ZenFS directly |
| Examples/persistence-manager helpers | gone; the README carries examples |

The 2.x line stays published and untouched until Apply Work has removed its v1 sync path.

## 4. Architecture

```
packages/core/src
  schema/        fluent builder, types                        (rewritten, same shape)
  migration/     introspect, diff, generate, apply             (rewritten, same behaviour)
  adapters/      SQLiteAdapter interface; wasm-opfs, wasm-idb, memory
  db/            Database: open, query, write, transaction, invalidation bus
  live/          LiveQuery, scope-aware invalidation, snapshot diffing
  sync/          outbox, overlay, drafts, cursors, pull applier, push, ticks
  react/         useLiveQuery, useDraftField, useOutboxCounts (thin; separate entry point)
```

Dependency direction: `react → sync → live → db → adapters`, `schema/migration → db`. Nothing above
`db` executes SQL directly.

## 5. `db` and `schema`

### 5.1 Database core
```ts
const db = await Database.open({ schema, adapter, migrate: 'auto' });   // 'auto' | 'plan' | 'off'
db.query<T>(sql, params)            // typed rows
db.queryOne<T>(sql, params)
db.execute(sql, params)             // for statements without result
db.transaction(async tx => { ... }) // tx has the same methods; one invalidation emission after commit
db.tables.<name>.insert/update/upsert/delete(...)   // generated from the schema, typed
db.schema                            // the declared schema
db.close()
```
Writes go through one path that records the written `(table, rowKey)` set on the transaction. On
commit the **invalidation bus** emits one event `{ tables: Map<table, Set<rowKey>> }`. There is no
per-row event.

**Server-truth guard.** Tables declared `.synced()` (section 5.2) reject direct writes from app code:
only the `PullApplier` and the `Outbox` committer hold the capability object required to write them.
This is enforced by the API (the write methods for synced tables are not exposed on `db.tables`), not
by convention.

### 5.2 Schema
Fluent style as today so `schema.ts` survives:
```ts
schema.table('c_work_task', t => {
  t.text('system_id').primary();
  t.integer('sync_seq');            // present on every synced table
  t.real('c_qty_installed');
  ...
}).synced({ key: 'system_id', scope: ['wo_no'] });
schema.table('outbox', ...)         // provided by the library, not the app
```
`.synced()` marks a table as server truth, names its row key and its scope columns. Auto-migration
adds the library's own tables (`outbox`, `sync_cursor`) and the `sync_seq` column when missing.

Auto-migration semantics unchanged from v2: additive by default, `plan` mode prints the operations,
table recreation only when a column type changes and only with `allowRecreate: true`.

## 6. `live` — live queries that are not brittle

```ts
const q = db.live<T>({
  sql: 'SELECT ... FROM c_work_task WHERE wo_no = ? ORDER BY ...',
  params: [woNo],
  reads: [{ table: 'c_work_task', scope: { wo_no: woNo } }],   // declared dependencies
  key: 'system_id',
});
q.subscribe(rows => ...); q.snapshot(); q.close();
```
Rules
1. **Scope-aware invalidation.** A query is re-run only when the invalidation event contains a row of
   one of its `reads` tables whose scope columns match (or when the writer did not report row keys,
   e.g. a full refresh — then every query on the table re-runs).
2. **One emission per transaction.** Invalidations are delivered after commit, coalesced.
3. **Emit only on change.** The new result is compared with the previous snapshot by `key` and by
   column values; identical → no emission. Row objects that did not change keep their identity, so
   React can skip re-rendering them.
4. **Overlay and holds inside the layer.** Before emission, rows pass through `Overlay.apply` (pending
   outbox values win) and `Drafts.apply` (held columns keep the last emitted value). No consumer can
   observe raw server truth for a column the outbox or a draft owns.
5. **Debounce is not needed**; coalescing per transaction plus emit-on-change already bounds emissions.
   A `minInterval` option exists for pathological writers (the 200-row pull applier commits once anyway).

## 7. `sync` — the primitives

### 7.1 Outbox
Table `outbox(id, table_name, system_id, column_name, old_value, new_value, changed_at, status,
group_id, batch_id, error_text, applied_at)`; statuses `pending | sending | applied | noop | rejected`.
```ts
outbox.record({ table, systemId, changes: { c_qty_installed: 5, rowstate: 'WORKSTARTED' } })
  // one change GROUP: writes the local rows' columns AND the outbox rows in one transaction
outbox.pending(); outbox.markSending(ids, batchId); outbox.applyResults(batchId, results, order)
outbox.resetSending(batchId); outbox.discard(id); outbox.retry(id); outbox.counts()
```
A change group is never split across batches by the push service, even at the 500-change cap
(a group larger than the cap is a programming error and throws at `record`).

### 7.2 Overlay
`Overlay.apply(table, rows)` replaces, for every row with `pending|sending` outbox entries, those
columns with the outbox `new_value`. Applied in `live` before emission and in `query` when
`{ overlay: true }` (default for synced tables).

### 7.3 Drafts
```ts
drafts.begin(table, systemId, column, seedValue)   // on focus
drafts.set(table, systemId, column, value)         // on keystroke
drafts.end(table, systemId, column)                 // on blur / Enter / save / Sync / route change / pagehide
   → if changed: outbox.record(...) (overlay takes over; any held server value for the column is dropped)
   → if unchanged: the held server value, if any, is applied now
```
While a draft exists, `Drafts.apply` holds the column at the last emitted value and holds a tombstone
for the row; held tombstones apply at `end`, after which the push answers `rejected` (row gone) and
the outbox shows it. Drafts live in the library's store keyed `(table, systemId, column)`, never in a
component, so virtualised unmounts cannot lose keystrokes. Lists stay live: only the focused
`(row, column)` is in draft.

### 7.4 Cursors and pull
`sync_cursor(table_name, scope, last_sync_seq)`. `PullApplier.apply(table, page)` upserts
`rows[].data` + `sync_seq`, deletes `removed`, skips columns with `pending|sending` outbox entries
for that row, honours draft holds, advances the cursor to `next`, and reports the written row keys to
the invalidation bus — one transaction per page. `PullService.pull(table, scope, { from: 'cursor' |
'window' | 0 })`: tick-driven pulls use `max(0, cursor − window)` (default 1000) because arrival order
is not commit order; manual refresh uses 0.

### 7.5 Push
`PushService`: debounce (default 2 s), builds one batch per push (`batchId` = uuid, ≤ 500 changes,
groups intact), `outbox.markSending`, `transport.push(batch)`, `outbox.applyResults`, then upserts the
returned `rows` through the same `PullApplier` path **with a seq-monotonic guard**: a row whose `seq` is
not above the local `sync_seq` is skipped. A push answer is a receipt, not a read — under a concurrent
write the loser is told `applied` and handed its own value, and a replayed batch returns the rows as
they were when it first ran (live findings FN-6/FN-8). Overlay rules apply — a column just marked
`applied` is no longer pending, so a newer server value lands. Network error → `resetSending`, backoff
5 s / 30 s / 2 min / next online or tick. `rejected` is terminal: the entry stays visible until the
user retries or discards it.

### 7.6 Ticks
`TickCoalescer.notify({ table, seq, scopes? })`: collects ticks for ~1.5 s, then triggers one pull per
`(table, scope)` the app has open, filtered by `scopes` when present. The app wires SignalR to it.

### 7.7 Transport (app-provided)
```ts
interface SyncTransport {
  pullRows(req: { table: string; scope?: string; after: number; limit?: number }): Promise<RowsPage>;
  push(batch: PushBatch): Promise<PushResult>;
}
```
`RowsPage`/`PushBatch`/`PushResult` mirror `cwork/docs/sync-v3/wire-format.md` exactly (camelCase,
`data` nested). Byte-length and `BatchId` validation is the API's job, but the library refuses
locally what it knows the server will refuse (value > 8000 bytes UTF-8).

## 8. React binding (`declarative-sqlite/react`)
- `useLiveQuery(spec)` → `useSyncExternalStore` over a `LiveQuery`; memoised snapshot; rows keyed by
  `key`.
- `useDraftField(table, systemId, column)` → `{ value, onFocus, onChange, onBlur, onKeyDown }`, the
  only way an editable field is written. Registers the exit paths (route change via a provider,
  `pagehide`/`visibilitychange` globally).
- `useOutboxCounts()` for the badge; `useSyncStatus()` for online/backoff state.

## 9. Testing
- `MemoryAdapter` (sql.js or the WASM build in Node) so the whole stack runs in vitest.
- Scenario tests, each a named test: pull during draft; pull between `record()` and the push
  response; rejected change; tombstone during edit; two devices interleaved (a fake transport with a
  scripted server); out-of-order arrival with the window; a 200-row page committing once; live query
  not re-run for a foreign scope; identical result not emitted.
- Migration tests: add table, add column, plan mode, type change with/without `allowRecreate`.

## 10. Migration path for Apply Work (Phase 3)
1. 3.0.0-alpha published from this repo; app pins it beside 2.x.
2. `schema.ts`: drop `.lww()`, add `.synced()` per mirror table (keys/scopes from the IFS column cache
   tables in `wire-format.md` §9).
3. `DatabaseService` opens v3; `SyncService` (2 300 lines) is replaced by `PullService`/`PushService`/
   `TickCoalescer` wiring + a `SignalR → TickCoalescer` adapter + an HTTP `SyncTransport`.
4. Editable fields move to `useDraftField`; lists to `useLiveQuery`.
5. First start of app v2.0: push remaining v2 dirty rows through the old path, drop and recreate the
   local DB, pull the user's recent work orders (Phase 3 Task 3.8).

## 11. Open questions for the owner
- Package layout: `declarative-sqlite` 3.0 with `react` as a subpath export (proposed), or a separate
  `declarative-sqlite-react` package?
- Keep `query-builder.ts` (fluent WHERE/ORDER helpers) or SQL strings only? Proposed: keep a minimal
  typed builder for the `db.tables.<name>` CRUD, SQL strings for reads.
- Should `.synced()` scope columns be validated against the server's `IS_SCOPE` list at startup
  (fetch the allow-list once) or trusted from `schema.ts`?
