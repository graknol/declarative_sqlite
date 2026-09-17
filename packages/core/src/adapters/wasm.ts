import type { SqlValue } from '../types';
import type { RunResult, SQLiteAdapter } from './adapter';

/** The initialised sqlite3 WASM namespace. Typed as `any` because the official build ships no types for `oo1`/`capi`. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Sqlite3Module = any;

/**
 * Everything the WASM-backed adapters share: binding parameters, stepping
 * statements, reading rows and exporting the database image. A subclass only
 * has to implement `open()` and assign `sqlite3` and `db`; how and where the
 * bytes are stored — in memory, in OPFS, or as an in-memory database with a
 * persisted snapshot — is the only thing that differs between the concrete
 * adapters. Extracted from `MemoryAdapter` so the OPFS and IndexedDB backends
 * get identical SQL semantics for free instead of re-implementing them.
 */
export abstract class WasmAdapterBase implements SQLiteAdapter {
  protected sqlite3: Sqlite3Module | undefined;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  protected db: any;

  abstract open(): Promise<void>;

  /** Closes the underlying database handle, if one is open, and marks this adapter as closed. */
  async close(): Promise<void> {
    if (!this.db) return;
    this.db.close();
    this.db = undefined;
  }

  /** Whether `open()` has produced a live database handle. */
  isOpen(): boolean {
    return this.db !== undefined;
  }

  /** Executes one or more SQL statements with no parameters and no result rows, such as DDL or transaction control. */
  async exec(sql: string): Promise<void> {
    this.ensureOpen();
    this.db.exec(sql);
  }

  /** Runs a parameterised query and returns every matching row. */
  async all<T>(sql: string, params: SqlValue[] = []): Promise<T[]> {
    this.ensureOpen();
    const stmt = this.db.prepare(sql);
    try {
      this.bind(stmt, params);
      const rows: T[] = [];
      while (stmt.step()) rows.push(stmt.get({}) as T);
      return rows;
    } finally {
      stmt.finalize();
    }
  }

  /** Runs a parameterised query and returns the first matching row, or `undefined` if there is none. */
  async get<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    return (await this.all<T>(sql, params))[0];
  }

  /**
   * Runs a parameterised write statement and reports how many rows changed
   * and the rowid of the last insert. The rowid is read through the sqlite3
   * C API (`sqlite3_last_insert_rowid`) rather than a convenience property on
   * the database object, because the WASM build's `oo1.DB` exposes no such
   * property; the C API call is the only reliable source.
   */
  async run(sql: string, params: SqlValue[] = []): Promise<RunResult> {
    this.ensureOpen();
    const stmt = this.db.prepare(sql);
    try {
      this.bind(stmt, params);
      stmt.step();
    } finally {
      stmt.finalize();
    }
    return {
      changes: this.db.changes(),
      lastInsertRowid: Number(this.sqlite3.capi.sqlite3_last_insert_rowid(this.db.pointer)),
    };
  }

  /** Serialises the whole database to an in-memory byte array, suitable for persisting or transferring elsewhere. */
  async export(): Promise<Uint8Array> {
    this.ensureOpen();
    return new Uint8Array(this.sqlite3.capi.sqlite3_js_db_export(this.db.pointer));
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  protected bind(stmt: any, params: SqlValue[]): void {
    for (let i = 0; i < params.length; i++) {
      stmt.bind(i + 1, params[i] ?? null);
    }
  }

  protected ensureOpen(): void {
    if (!this.db) throw new Error('Database is not open. Call open() first.');
  }
}
