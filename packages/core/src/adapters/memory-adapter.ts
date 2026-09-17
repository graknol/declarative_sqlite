import { createRequire } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import type { SqlValue } from '../types';
import type { RunResult, SQLiteAdapter } from './adapter';

/** The initialised sqlite3 WASM namespace. Typed as `any` because the official build ships no types for `oo1`/`capi`. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Sqlite3Module = any;

/**
 * Resolves and loads the Node entry point of `@sqlite.org/sqlite-wasm`
 * (`sqlite-wasm/jswasm/sqlite3-node.mjs`). That file is not listed in the
 * package's `exports` map, so importing it by specifier throws
 * `ERR_PACKAGE_PATH_NOT_EXPORTED` under plain Node; only `.` and
 * `./package.json` are exported. We resolve `./package.json` (which *is*
 * exported) with `createRequire`, then join its directory to the real file
 * and import that absolute `file://` URL instead, which bypasses the
 * `exports` map entirely and works both under vitest and in a consuming
 * Node process with no bundler-specific alias required.
 */
async function loadNodeSqlite3(): Promise<Sqlite3Module> {
  const require = createRequire(import.meta.url);
  const pkgJson = require.resolve('@sqlite.org/sqlite-wasm/package.json');
  const entry = path.join(path.dirname(pkgJson), 'sqlite-wasm', 'jswasm', 'sqlite3-node.mjs');
  return import(/* @vite-ignore */ pathToFileURL(entry).href);
}

/**
 * Loads the official SQLite WASM build for the current environment: the
 * `sqlite3-node.mjs` entry under Node (tests) and the package's browser entry
 * everywhere else. The module is initialised once per process and cached, so
 * opening several adapters costs one WASM instantiation.
 */
let modulePromise: Promise<Sqlite3Module> | undefined;

export async function loadSqlite3(wasmDir?: string): Promise<Sqlite3Module> {
  if (!modulePromise) {
    modulePromise = (async () => {
      const isNode = typeof process !== 'undefined' && process.versions?.node !== undefined;
      const mod = isNode ? await loadNodeSqlite3() : await import('@sqlite.org/sqlite-wasm');
      const init = (mod as { default: (config: unknown) => Promise<Sqlite3Module> }).default;
      const config: Record<string, unknown> = { print: () => {}, printErr: console.error };
      if (wasmDir) {
        config['locateFile'] = (file: string) => `${wasmDir}/${file}`;
      }
      return init(config);
    })();
  }
  return modulePromise;
}

/**
 * An in-memory SQLite database over the official WASM build. It is the adapter
 * every test in this package uses and the last-resort browser backend when
 * neither OPFS nor IndexedDB is usable: nothing survives a reload, but the SQL
 * semantics are byte-for-byte the ones the persistent adapters give.
 */
export class MemoryAdapter implements SQLiteAdapter {
  protected sqlite3: Sqlite3Module | undefined;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  protected db: any;

  async open(): Promise<void> {
    if (this.db) return;
    this.sqlite3 = await loadSqlite3();
    this.db = new this.sqlite3.oo1.DB(':memory:');
  }

  async close(): Promise<void> {
    if (!this.db) return;
    this.db.close();
    this.db = undefined;
  }

  isOpen(): boolean {
    return this.db !== undefined;
  }

  async exec(sql: string): Promise<void> {
    this.ensureOpen();
    this.db.exec(sql);
  }

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

  async get<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    const rows = await this.all<T>(sql, params);
    return rows[0];
  }

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
