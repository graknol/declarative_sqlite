import type { SqlValue } from '../types';

/** What a write statement reports back: how many rows it changed and the rowid SQLite assigned to the last insert. */
export interface RunResult {
  changes: number;
  lastInsertRowid: number;
}

/**
 * The whole surface the library needs from a SQLite build. It is deliberately
 * statement-free — callers pass a SQL string and a parameter array — so that an
 * adapter can be a WASM database, a native bridge or a test double without
 * modelling prepared statements. Transactions are NOT part of this interface:
 * the `db` layer issues `BEGIN IMMEDIATE`/`COMMIT`/`ROLLBACK` through `exec`
 * so that the single write path owns transaction boundaries.
 */
export interface SQLiteAdapter {
  open(): Promise<void>;
  close(): Promise<void>;
  exec(sql: string): Promise<void>;
  all<T = Record<string, SqlValue>>(sql: string, params?: SqlValue[]): Promise<T[]>;
  get<T = Record<string, SqlValue>>(sql: string, params?: SqlValue[]): Promise<T | undefined>;
  run(sql: string, params?: SqlValue[]): Promise<RunResult>;
  isOpen(): boolean;
  export(): Promise<Uint8Array>;
}
