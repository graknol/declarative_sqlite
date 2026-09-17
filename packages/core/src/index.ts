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
