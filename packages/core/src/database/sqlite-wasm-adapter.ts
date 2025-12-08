import { SQLiteAdapter, PreparedStatement, RunResult } from '../adapters/adapter.interface';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';

/**
 * Adapter for @sqlite.org/sqlite-wasm (Browser-compatible SQLite)
 * Supports PWA, Capacitor, and other browser environments
 */
export class SqliteWasmAdapter implements SQLiteAdapter {
  private sqlite3: any = null;
  private db: any = null;
  private initialized = false;

  async initialize(): Promise<void> {
    if (this.initialized) return;
    
    this.sqlite3 = await sqlite3InitModule({
      print: console.log,
      printErr: console.error,
    });
    this.initialized = true;
  }

  async open(path: string): Promise<void> {
    await this.initialize();
    
    // For in-memory databases or OPFS (Origin Private File System)
    if (path === ':memory:') {
      this.db = new this.sqlite3.oo1.DB();
    } else {
      // Use OPFS for persistent storage in browser
      // Note: OPFS requires origin-private-file-system support
      this.db = new this.sqlite3.oo1.DB(path, 'c');
    }
    
    // Enable WAL mode for better concurrency
    this.db.exec('PRAGMA journal_mode = WAL');
  }

  async close(): Promise<void> {
    if (this.db) {
      this.db.close();
      this.db = null;
    }
  }

  async exec(sql: string): Promise<void> {
    this.ensureOpen();
    this.db.exec(sql);
  }

  prepare(sql: string): PreparedStatement {
    this.ensureOpen();
    const stmt = this.db.prepare(sql);

    return {
      run: async (...params: any[]): Promise<RunResult> => {
        stmt.bind(params);
        stmt.step();
        const changes = this.db.changes();
        const lastInsertRowid = this.db.lastInsertRowid;
        stmt.reset();
        
        return {
          lastInsertRowid,
          changes,
        };
      },
      get: async <T = any>(...params: any[]): Promise<T | undefined> => {
        stmt.bind(params);
        const hasRow = stmt.step();
        
        if (!hasRow) {
          stmt.reset();
          return undefined;
        }
        
        const result = stmt.get({});
        stmt.reset();
        return result as T;
      },
      all: async <T = any>(...params: any[]): Promise<T[]> => {
        stmt.bind(params);
        const results: T[] = [];
        
        while (stmt.step()) {
          results.push(stmt.get({}) as T);
        }
        
        stmt.reset();
        return results;
      },
      finalize: async (): Promise<void> => {
        stmt.finalize();
      },
    };
  }

  async transaction<T>(callback: () => Promise<T>): Promise<T> {
    this.ensureOpen();

    try {
      this.db.exec('BEGIN');
      const result = await callback();
      this.db.exec('COMMIT');
      return result;
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  isOpen(): boolean {
    return this.db !== null && this.db !== undefined;
  }

  /**
   * Get the underlying sqlite-wasm database instance
   */
  getDatabase(): any {
    return this.db;
  }

  private ensureOpen(): void {
    if (!this.isOpen()) {
      throw new Error('Database is not open. Call open() first.');
    }
  }
}
