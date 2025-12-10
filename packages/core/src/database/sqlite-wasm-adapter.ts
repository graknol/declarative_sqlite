import { SQLiteAdapter, PreparedStatement, RunResult } from '../adapters/adapter.interface';

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
    
    // Dynamically import the appropriate SQLite module based on environment
    let sqlite3InitModule: any;
    
    if (typeof window === 'undefined' || typeof process !== 'undefined') {
      // Node.js environment (tests) - use direct file system access
      try {
        // Try to load node-specific module directly
        const modulePath = '@sqlite.org/sqlite-wasm/sqlite-wasm/jswasm/sqlite3-node.mjs';
        const nodeModule = await import(modulePath);
        sqlite3InitModule = nodeModule.default;
      } catch (error) {
        // Fallback: Use standard module with createRequire workaround
        console.warn('Using fallback SQLite initialization for Node.js environment');
        const standardModule = await import('@sqlite.org/sqlite-wasm');
        sqlite3InitModule = standardModule.default;
      }
    } else {
      // Browser environment - use the standard build
      const browserModule = await import('@sqlite.org/sqlite-wasm');
      sqlite3InitModule = browserModule.default;
    }
    
    this.sqlite3 = await sqlite3InitModule({
      print: console.log,
      printErr: console.error,
    });
    this.initialized = true;
  }

  async open(path: string): Promise<void> {
    await this.initialize();
    
    // Handle different storage backends
    if (path === ':memory:') {
      // In-memory database
      this.db = new this.sqlite3.oo1.DB();
    } else if (path.startsWith('indexeddb://')) {
      // IndexedDB-backed storage using IDBBatchAtomicVFS
      const dbName = path.replace('indexeddb://', '');
      await this.openWithIndexedDB(dbName);
    } else if (path.startsWith('/opfs/')) {
      // OPFS (Origin Private File System) storage
      const dbName = path.replace('/opfs/', '');
      await this.openWithOPFS(dbName);
    } else {
      // Default: file system or OPFS based on environment
      try {
        this.db = new this.sqlite3.oo1.DB(path, 'c');
      } catch (error) {
        console.warn('Failed to open database with path, falling back to in-memory:', error);
        this.db = new this.sqlite3.oo1.DB();
      }
    }
  }

  /**
   * Open database with IndexedDB VFS backend
   */
  private async openWithIndexedDB(dbName: string): Promise<void> {
    // Check if IDBBatchAtomicVFS is available
    if (!this.sqlite3.capi.sqlite3_vfs_find('idb-batch-atomic')) {
      console.warn('IDBBatchAtomicVFS not available, falling back to in-memory');
      this.db = new this.sqlite3.oo1.DB();
      return;
    }
    
    try {
      // Use IndexedDB VFS
      this.db = new this.sqlite3.oo1.DB(dbName, 'c', 'idb-batch-atomic');
    } catch (error) {
      console.warn('Failed to open IndexedDB database, falling back to in-memory:', error);
      this.db = new this.sqlite3.oo1.DB();
    }
  }

  /**
   * Open database with OPFS VFS backend
   */
  private async openWithOPFS(dbName: string): Promise<void> {
    // Check if OPFS VFS is available
    const opfsVfs = this.sqlite3.capi.sqlite3_vfs_find('opfs');
    if (!opfsVfs) {
      console.warn('OPFS VFS not available, falling back to in-memory');
      this.db = new this.sqlite3.oo1.DB();
      return;
    }
    
    try {
      // Use OPFS VFS
      this.db = new this.sqlite3.oo1.DB(dbName, 'c', 'opfs');
    } catch (error) {
      console.warn('Failed to open OPFS database, falling back to in-memory:', error);
      this.db = new this.sqlite3.oo1.DB();
    }
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
        if (params.length > 0) {
          // sqlite-wasm bind() expects each parameter individually
          for (let i = 0; i < params.length; i++) {
            stmt.bind(i + 1, params[i]);
          }
        }
        stmt.step();
        
        const changes = this.db.changes();
        let lastInsertRowid: number | bigint = 0;
        
        // Access lastInsertRowid property (must be called before reset())
        if ('lastInsertRowid' in this.db) {
          lastInsertRowid = this.db.lastInsertRowid;
        } else if ('last_insert_rowid' in this.db) {
          lastInsertRowid = this.db.last_insert_rowid;
        }
        
        // Ensure lastInsertRowid is a number
        if (typeof lastInsertRowid === 'bigint') {
          lastInsertRowid = Number(lastInsertRowid);
        }
        
        stmt.reset();
        
        return {
          lastInsertRowid: lastInsertRowid as number,
          changes,
        };
      },
      get: async <T = any>(...params: any[]): Promise<T | undefined> => {
        if (params.length > 0) {
          for (let i = 0; i < params.length; i++) {
            stmt.bind(i + 1, params[i]);
          }
        }
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
        if (params.length > 0) {
          for (let i = 0; i < params.length; i++) {
            stmt.bind(i + 1, params[i]);
          }
        }
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
   * Export the database as a Uint8Array
   */
  async exportDatabase(): Promise<Uint8Array> {
    this.ensureOpen();
    
    // Use sqlite3's export functionality
    // The method varies based on the VFS backend
    try {
      // Try the standard export method
      if (typeof this.db.exportDatabase === 'function') {
        return this.db.exportDatabase();
      }
      
      // For sqlite-wasm, use the C API
      const exported = this.sqlite3.capi.sqlite3_js_db_export(this.db.pointer);
      return new Uint8Array(exported);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`Failed to export database: ${message}`);
    }
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
