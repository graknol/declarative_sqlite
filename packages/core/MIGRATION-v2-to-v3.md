# Migrating Apply Work from declarative-sqlite 2.x to 3.0

v3 is a full rewrite, not an incremental release: no v2 module carries over.
This is the executable contract for moving Apply Work's application code onto
it. It assumes you have already read the [README](./README.md) for what each
piece *is* — this document is only about what changes in code that already
exists.

## 1. What changes, in one table

| v2 | v3 |
|---|---|
| `SchemaBuilder` | Survives, same fluent shape — see §2 |
| `.lww()` on a column | Gone. The server decides and logs; nothing about a column needs to say so locally |
| `*__hlc` shadow columns | Gone |
| `Hlc`, `db.generateHLC()` | Gone |
| `dirtyRowStore` | Gone — replaced by the library's own `outbox` table |
| `bulkLoad(..., forceOverwrite)` | Gone |
| `AdapterFactory` | Gone — replaced by `openAdapter({ name, wasmDir })` |
| `DeclarativeDatabase` | `Database` (`Database.open<AppRows, SyncedTableName>({ schema, adapter })`) |
| `db.stream(...)` / `subscribeToTable(...)` | `db.live(spec)` (root entry point) / `useLiveQuery(spec)` (React) |
| `db.update(...)` on a synced table | `sync.outbox.record({ table, systemId, changes })` — `db.tables.<synced table>` has no write methods at all, so the old call site is a type error, not a runtime one |
| `SyncService.pullData` / `pullSpecificTables` | `sync.pull.pull(table, scope)` |
| `SyncService.pushData` | `sync.push.pushNow()` / `sync.push.schedule()` |
| `SyncService.triggerDebouncedSync` | `sync.push.schedule()` |
| SignalR `TableChanged` handler | `sync.ticks.notify({ table, seq, scopes })` |
| `recentlyPushedTables`, the ETag cache | Gone, nothing replaces them |
| `RemovalStagingService` | Gone, nothing replaces it (see §8) |

## 2. `src/schema.ts`

`.lww()` is deleted from every column; `.synced({ key, scope })` is added once
per synced table, after the table body closes:

```ts
// v2
builder.table('c_work_task', (table) => {
  table.real('wo_no').notNull(0.0);
  table.real('c_qty_installed').lww();
  table.text('rowstate').maxLength(100).lww();
  table.integer('system_removed').notNull(0);
  table.key('system_id').primary();
});

// v3
schema.table('c_work_task', (table) => {
  table.real('wo_no').notNull(0.0);
  table.real('c_qty_installed');
  table.text('rowstate').maxLength(100);
  table.integer('system_removed').notNull(0);
  table.key('system_id').primary();
}).synced({ key: 'system_id', scope: ['wo_no'] });
```

Two things the v2 body no longer needs to spell out, because `TableBuilder`
now adds them itself when the app's own schema doesn't declare them:
`system_id` (TEXT, guid) and `system_removed` (INTEGER) on every table, and
`sync_seq` (INTEGER) on a `.synced()` one. Leaving your existing explicit
declarations in place (as in the sample above) is harmless — the builder only
adds what's missing.

`scope` is what a pull or a tick can filter by; it must name columns already
declared on the table. Per mirror table:

| Tables | `scope` |
|---|---|
| `c_work_task`, `c_work_order`, `c_maint_material_req_line`, `c_work_order_attachment`, `c_work_order_note` | `['wo_no']` |
| `c_checklist`, `c_check_item`, `c_approval_line` | `['task_seq']` |
| `c_doc_ref_object`, `c_aw_proarc_doc_rev_conn`, `c_ncr_object_connection`, `c_wo_document` | `['lu_name', 'key_ref']` |
| `c_aw_shipment` | `['receiver_id']` |
| `c_aw_shipment_line` | `['shipment_id']` |
| `c_ncr` | `['ncr_no']` |
| `c_apply_work_user`, `c_aw_inventory_location`, `c_aw_proarc_doc_rev`, `c_edm_file`, `c_work_file` (`ALLOW_FULL_PULL = yes`) | `[]` — pulled whole |

Delete `outbox` and `sync_cursor` from `schema.ts` if an earlier v3 spike ever
added them by hand: `SchemaBuilder.table()` throws `SchemaError` if the app
declares either name, because `SchemaBuilder.build()` always appends both
itself (see `OUTBOX_TABLE`/`SYNC_CURSOR_TABLE` in `src/schema/library-tables.ts`).

## 3. `src/v2/services/DatabaseService.ts`

Replace `AdapterFactory.create(...)` and the Safari-version branching with
`openAdapter`, keeping the Capacitor path as a caller-supplied adapter since
`openAdapter` only knows about the browser backends (OPFS, IndexedDB, memory):

```ts
import { openAdapter, Database, createSyncRuntime, IndexedDbAdapter } from 'declarative-sqlite';

const opened = isNative
  ? { adapter: await openCapacitorAdapter(dbName), backend: 'native' as const, warnings: [] }
  : await openAdapter({ name: dbName, wasmDir: '/assets' });

for (const warning of opened.warnings) console.warn('[db]', warning);

this.db = await Database.open<AppRows, SyncedTableName>({ schema, adapter: opened.adapter });
this.sync = await createSyncRuntime({ db: this.db, transport: new HttpSyncTransport(api, domain), deviceId });

if (opened.backend === 'indexeddb') {
  // IndexedDbAdapter persists the whole image after writes settle, not
  // incrementally (see README → Adapters), so flush explicitly before the
  // page can be killed. `opened.adapter` is typed `SQLiteAdapter`, which has
  // no `flush()` — narrow it because we already know the backend.
  window.addEventListener('pagehide', () => {
    void (opened.adapter as IndexedDbAdapter).flush();
  });
}
```

`AppRows` is a `RowMap` (`Record<string, Record<string, unknown>>`) built from
the 19 interfaces already declared in `schema.ts` — one property per table
name, keyed to its row shape:

```ts
type AppRows = {
  c_work_task: CWorkTask;
  c_work_order: CWorkOrder;
  // ...the remaining 17 tables
};

type SyncedTableName = 'c_work_task' | 'c_work_order' | /* ...every `.synced()` table */;
```

`Database.open<AppRows, SyncedTableName>(...)` uses that pair to type
`db.tables`: a name in `SyncedTableName` gets `SyncedTableApi` (`get` only,
enforced by the type — there is no write method to cast around), everything
else gets full CRUD (`get`/`insert`/`update`/`upsert`/`delete`).

The 30-second `PRAGMA wal_checkpoint(TRUNCATE)` timer goes away entirely —
OPFS commits durably on every write and IndexedDB's own debounce-then-flush
(above) is the only persistence timer left.

## 4. Replacing `SyncService.ts`

| v2 | v3 |
|---|---|
| `pullData(table)` / `pullSpecificTables(tables)` | `sync.pull.pull(table, scope)` — one call per `(table, scope)`, not a batch of tables |
| `pushData()` | `sync.push.pushNow()` for an immediate, awaited push; `sync.push.schedule()` to debounce (2 s default) |
| `triggerDebouncedSync()` | `sync.push.schedule()` |
| SignalR `TableChanged` handler | `sync.ticks.notify({ table, seq, scopes })` — the runtime coalesces ticks for ~1.5 s and pulls only the `(table, scope)` pairs the app has registered as open via `sync.pull.registerScope` |
| the Sync button's handler | see below |
| `recentlyPushedTables` | deleted, nothing replaces it — the seq-monotonic guard on every applied row makes it unnecessary |
| the ETag cache | deleted, nothing replaces it — a pull is a cursor read, not a conditional GET |
| `RemovalStagingService` | deleted, nothing replaces it (§8) |

The Sync button's handler becomes:

```ts
async function onSyncButtonPressed(table: string, scope: ScopeValues) {
  await sync.drafts.endAll();       // commit every open edit first
  await sync.push.pushNow();        // send whatever is pending
  await sync.pull.pull(table, scope, { from: 0 }); // read the scope whole
}
```

`endAll()` first matters because a manual Sync is one of the draft lifecycle's
explicit exit paths (README → React): it must commit in-progress keystrokes to
the outbox before the push, not race them.

## 5. The `SyncTransport` implementation

The library never speaks HTTP — `SyncTransport` (`src/sync/transport.ts`) is
the only thing it asks the app for:

```ts
import type { SyncTransport, PullRequest, RowsPage, PushBatch, PushResult } from 'declarative-sqlite';

export class HttpSyncTransport implements SyncTransport {
  constructor(
    private readonly api: ApiClient,
    private readonly domain: string,
  ) {}

  async pullRows(req: PullRequest): Promise<RowsPage> {
    const params = new URLSearchParams({ domain: this.domain, table: req.table, after: String(req.after) });
    if (req.scope) params.set('scope', req.scope);
    if (req.limit) params.set('limit', String(req.limit));
    return this.api.get<RowsPage>(`/sync/rows?${params.toString()}`);
  }

  async push(batch: PushBatch): Promise<PushResult> {
    return this.api.post<PushResult>(`/sync/push?domain=${encodeURIComponent(this.domain)}`, batch);
  }
}
```

A rejected promise from either method is treated as a network error and
retried with backoff. That is wrong for a 4xx the server has already decided
to refuse (a validation failure, a stale `wo_no`) — those should be filed as
`rejected` immediately, not retried forever. `HttpSyncTransport` itself has no
say in this; tell `createSyncRuntime` how to recognise one instead, via the
`isTerminalError` option:

```ts
const sync = await createSyncRuntime({
  db,
  transport: new HttpSyncTransport(api, domain),
  deviceId,
  isTerminalError: (error) => error instanceof ApiError && error.status >= 400 && error.status < 500,
});
```

`ApiClient` should throw something `isTerminalError` can recognise by status
code — e.g. an `ApiError` carrying the HTTP status — rather than swallowing it
into a generic `Error`.

## 6. Hooks and components

| v2 | v3 |
|---|---|
| `useDatabaseRecord().updateField(table, id, field, value)` | `sync.outbox.record({ table, systemId, changes: { [field]: value } })` for a direct write; `useDraftField(table, systemId, column, currentValue)` for anything a user types into (see below) |
| the `__hlc` branch inside `updateField` | deleted — there is no HLC to stamp |
| `db.generateHLC()` | deleted |
| a list built on `db.stream(...)`/`subscribeToTable(...)` | `useLiveQuery<T>({ sql, params, reads, key })` |
| `useTableSync(table, scope)` | a `useEffect` that registers the scope and pulls once (below) |

Every editable field moves to `useDraftField`, which is the only supported way
to write an editable cell (README → React): it starts a draft on focus, sends
the outbox entry (or releases an unchanged value) on blur/Enter/Escape, and is
also ended by `SyncProvider`'s global exit paths (`pagehide`,
`visibilitychange`, unmount, a `routeKey` change) so backgrounding the app or
navigating away can never lose or race a keystroke.

```tsx
// v2
<input
  value={task.c_qty_installed}
  onChange={(e) => updateField('c_work_task', task.system_id, 'c_qty_installed', Number(e.target.value))}
/>

// v3
const field = useDraftField('c_work_task', task.system_id, 'c_qty_installed', task.c_qty_installed);
<input value={field.value} onFocus={field.onFocus} onChange={field.onChange}
       onBlur={field.onBlur} onKeyDown={field.onKeyDown} />
```

`useTableSync` becomes an effect that registers the scope as open (so
tick-driven pulls know to refresh it) and pulls it once on mount, deregistering
on cleanup:

```ts
function useTableSync(table: string, scope: ScopeValues) {
  const sync = useSyncRuntime();
  useEffect(() => {
    const unregister = sync.pull.registerScope(table, scope);
    void sync.pull.pull(table, scope);
    return unregister;
  }, [sync, table, JSON.stringify(scope)]);
}
```

## 7. The one-time upgrade (Phase 3 Task 3.8)

On first launch after the update, an installed client still has its v2
database on disk with a `__dirty_rows` table the v3 schema has never heard of.
The upgrade path: push whatever v2 left dirty through the *old* sync path one
last time, close the v2 database, delete its storage (the OPFS file or the
IndexedDB image — whichever `AdapterFactory` was using), open v3 fresh (which
creates the schema, including `outbox` and `sync_cursor`, from nothing), then
pull the last ten work orders the user had open so the app isn't empty on
first paint.

The check that decides whether this runs at all — a v3 open against a
database that still carries the v2 table — is a plain `sqlite_master` lookup
through `db.queryOne`:

```ts
const legacy = await db.queryOne<{ n: number }>(
  `SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' AND name = '__dirty_rows'`,
);
if ((legacy?.n ?? 0) > 0) await runLegacyUpgrade();
```

Run this check, and `runLegacyUpgrade()` if it fires, **before** calling
`Database.open` with the v3 schema — the v2 storage location and the v3 one
are the same file/image name, so the legacy database must be drained and
deleted first.

## 8. What v3 does not do

`PushBatch` (`src/sync/wire.ts`) is modify-only: it carries column changes,
not row creation or deletion, and `system_removed` is not a writable column
through `sync.outbox.record` — the server, not the client, decides a row is
gone, and the client only ever finds out by pulling it back with
`removed: true`. `sync.outbox.record` records a change group per existing
row and never invents one.

That means `BulkNew` and `BulkRemove` — creating a `c_work_order_note` or
deleting a `c_maint_material_req_line` locally — have no v3 replacement yet.
They stay exactly as they are in the v2 app code until IFS Phase-2 task 2.0
defines what a create/delete wire message looks like; `RemovalStagingService`
in particular has nothing to migrate to and should be deleted only once its
callers are moved onto whatever that task produces, not before.
