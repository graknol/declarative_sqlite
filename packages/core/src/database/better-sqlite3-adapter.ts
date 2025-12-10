import { SQLiteAdapter, PreparedStatement, RunResult } from '../adapters/adapter.interface';

/**
 * Adapter for better-sqlite3 (Node.js synchronous SQLite)
 * Used primarily for testing
 */
export class BetterSqlite3Adapter implements SQLiteAdapter {
  private db: any;
  private Database: any;

  /**
   * Create a new BetterSqlite3Adapter
   * @param Database - The better-sqlite3 Database constructor (import('better-sqlite3'))
   */
  constructor(Database: any) {
    this.Database = Database;
  }

  async open(path: string): Promise<void> {
    this.db = new this.Database(path);
    this.db.pragma('journal_mode = WAL'); // Better concurrency
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
        const info = stmt.run(...params);
        return {
          lastInsertRowid: info.lastInsertRowid,
          changes: info.changes,
        };
      },
      get: async <T = any>(...params: any[]): Promise<T | undefined> => {
        return stmt.get(...params);
      },
      all: async <T = any>(...params: any[]): Promise<T[]> => {
        return stmt.all(...params);
      },
      finalize: async (): Promise<void> => {
        // better-sqlite3 doesn't require explicit finalization
      },
    };
  }

  async transaction<T>(callback: () => Promise<T>): Promise<T> {
    this.ensureOpen();

    // better-sqlite3 transactions must be synchronous, but our callback is async
    // So we manually handle BEGIN/COMMIT/ROLLBACK
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
   * Export the database as a Uint8Array
   */
  async exportDatabase(): Promise<Uint8Array> {
    this.ensureOpen();
    
    // better-sqlite3 provides a serialize method
    const buffer = this.db.serialize();
    return new Uint8Array(buffer);
  }

  /**
   * Get the underlying better-sqlite3 database instance
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
