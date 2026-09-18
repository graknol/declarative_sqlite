/**
 * declarative-sqlite — an offline-first sync data layer for SQLite in the browser.
 * The package is built in layers: `adapters` (raw SQLite), `db` (one write path and
 * an invalidation bus), `live` (queries that re-run only for their own scope),
 * `sync` (outbox, drafts, cursors, pull and push) and the `declarative-sqlite/react`
 * subpath. Import `Database` and a schema to get started; see README.md.
 */
export const VERSION = '3.0.0-alpha.1';

export type { SqlValue, Row, ScopeValues } from './types';
export type { SQLiteAdapter, RunResult } from './adapters/adapter';
export { MemoryAdapter, loadSqlite3 } from './adapters/memory-adapter';
export { OpfsAdapter } from './adapters/opfs-adapter';
export { IndexedDbAdapter } from './adapters/indexeddb-adapter';
export { WasmAdapterBase } from './adapters/wasm';
export { openAdapter } from './adapters/open-adapter';
export type { AdapterBackend, AdapterCapabilities, OpenAdapterOptions, OpenedAdapter } from './adapters/open-adapter';

export { SchemaBuilder } from './schema/schema-builder';
export type { TableHandle } from './schema/schema-builder';
export { TableBuilder, KeyBuilder, SYSTEM_ID_COLUMN, SYNC_SEQ_COLUMN, SYSTEM_REMOVED_COLUMN } from './schema/table-builder';
export { ColumnBuilder } from './schema/column-builder';
export { OUTBOX_TABLE, SYNC_CURSOR_TABLE } from './schema/library-tables';
export { formatScope, parseScope, scopeKey, scopeMatches, validateScopes, ScopeError } from './schema/scopes';
export type { ScopeAllowList } from './schema/scopes';
export { SchemaError } from './schema/types';
export type { Schema, TableDef, ColumnDef, KeyDef, KeyType, SyncedDef, StorageType, LogicalType } from './schema/types';

export { introspect } from './migration/introspect';
export { diffSchema } from './migration/diff';
export { generateMigration, createTableSql, MigrationBlockedError } from './migration/generate';
export { planMigration, runMigration } from './migration/migrate';
export type { MigrationDiff, TableAlteration, ColumnRetype } from './migration/diff';
export type { MigrationOperation } from './migration/generate';
export type { MigrationMode, MigrationPlan } from './migration/migrate';

export { Database, DatabaseError } from './db/database';
export { Transaction } from './db/transaction';
export { InvalidationBus } from './db/invalidation-bus';
export { quoteIdentifier } from './db/sql';
export { toSqlValue } from './db/tables';
export type { DatabaseOptions } from './db/database';
export type { InvalidationEvent, TableInvalidation } from './db/invalidation-bus';
export type { RowMap, TableApi, SyncedTableApi, TableApis } from './db/tables';
export type { ServerWriter } from './db/server-truth';

// Scripted server every test in this package runs against, exported so applications can use it in their own tests.
export { FakeTransport } from './testing/fake-transport';

export { LiveQuery } from './live/live-query';
export { LiveRegistry } from './live/registry';
export { diffRows } from './live/diff-rows';
export type { LiveQuerySpec, ReadDependency, RowTransform } from './live/live-query';

export { Outbox, OutboxError } from './sync/outbox';
export { Overlay } from './sync/overlay';
export { Drafts } from './sync/drafts';
export { CursorStore } from './sync/cursor-store';
export { PullApplier } from './sync/pull-applier';
export { PullService } from './sync/pull-service';
export { PushService } from './sync/push-service';
export { TickCoalescer } from './sync/tick-coalescer';
export { createSyncRuntime } from './sync/runtime';
export type { OutboxEntry, OutboxStatus, RecordRequest } from './sync/outbox';
export type { DraftState } from './sync/drafts';
export type { CursorRow } from './sync/cursor-store';
export type { ApplyOptions, ApplyReport } from './sync/pull-applier';
export type { PullOptions, PullReport } from './sync/pull-service';
export type { PushOutcome, PushServiceOptions, SyncStatus } from './sync/push-service';
export type { SyncTransport } from './sync/transport';
export type { RowsPage, RowDoc, PullRequest, PushBatch, PushResult } from './sync/wire';
export {
  encodeScalar, decodeScalar, newBatchId, toWireTable, toWireColumn, fromWireData,
  ValueTooLongError, MAX_VALUE_CHARS, MAX_BATCH_CHANGES, MAX_BATCH_ID_CHARS, PULL_WINDOW, DEFAULT_PAGE_LIMIT,
} from './sync/wire';
export type { PushChange, PushChangeResult, PushResultCode } from './sync/wire';
export type { Tick } from './sync/tick-coalescer';
export type { SyncRuntime, SyncRuntimeOptions } from './sync/runtime';
