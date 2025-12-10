import { SQLiteAdapter } from "../adapters/adapter.interface";
import { SqliteWasmAdapter } from "./sqlite-wasm-adapter";
import {
  PersistenceConfig,
  StorageBackend,
  mergePersistenceConfig,
} from "./persistence-config";
import { PersistenceManager } from "./persistence-manager";

/**
 * Factory for creating and configuring SQLite adapters with persistence
 */
export class AdapterFactory {
  /**
   * Create and open a SQLite adapter with persistence configuration
   *
   * @example
   * ```typescript
   * // Auto-detect best backend
   * const adapter = await AdapterFactory.create({
   *   name: 'myapp.db',
   * });
   *
   * // Use specific backend
   * const adapter = await AdapterFactory.create({
   *   backend: StorageBackend.OPFS,
   *   name: 'myapp.db',
   *   enableWAL: true,
   * });
   *
   * // In-memory database
   * const adapter = await AdapterFactory.create({
   *   backend: StorageBackend.Memory,
   * });
   * ```
   */
  static async create(
    config?: Partial<PersistenceConfig>
  ): Promise<SQLiteAdapter> {
    const mergedConfig = mergePersistenceConfig(config);
    
    // Create SqliteWasmAdapter - it handles all backends via VFS
    const adapter = new SqliteWasmAdapter();

    // Use PersistenceManager to open with configuration
    const manager = new PersistenceManager(adapter, mergedConfig);
    await manager.open();

    return adapter;
  }

  /**
   * Create adapter instance without opening
   */
  static async createAdapter(): Promise<SQLiteAdapter> {
    return new SqliteWasmAdapter();
  }

  /**
   * Create a persistence manager for an existing adapter
   */
  static createPersistenceManager(
    adapter: SQLiteAdapter,
    config?: Partial<PersistenceConfig>
  ): PersistenceManager {
    return new PersistenceManager(adapter, config);
  }

  /**
   * Quick setup for common scenarios
   */
  static async quickSetup(
    scenario: "node" | "browser" | "testing"
  ): Promise<SQLiteAdapter> {
    switch (scenario) {
      case "node":
        return this.create({
          backend: StorageBackend.FileSystem,
          name: "app.db",
          enableWAL: true,
          synchronous: "NORMAL",
        });

      case "browser":
        return this.create({
          backend: StorageBackend.Auto,
          name: "app.db",
          enableWAL: true,
          synchronous: "NORMAL",
        });

      case "testing":
        return this.create({
          backend: StorageBackend.Memory,
          name: ":memory:",
        });

      default:
        throw new Error(`Unknown scenario: ${scenario}`);
    }
  }
}

/**
 * Convenience functions for common use cases
 */

/**
 * Create an in-memory database (no persistence)
 */
export async function createMemoryAdapter(): Promise<SQLiteAdapter> {
  return AdapterFactory.create({
    backend: StorageBackend.Memory,
  });
}

/**
 * Create a file-based database (works in Node.js and browsers with file system access)
 */
export async function createFileAdapter(path: string): Promise<SQLiteAdapter> {
  return AdapterFactory.create({
    backend: StorageBackend.Auto,
    name: path,
  });
}

/**
 * Create a browser database with best available backend
 */
export async function createBrowserAdapter(name: string): Promise<SQLiteAdapter> {
  return AdapterFactory.create({
    backend: StorageBackend.Auto,
    name,
  });
}

/**
 * Create an OPFS-backed database (modern browsers)
 */
export async function createOPFSAdapter(name: string): Promise<SQLiteAdapter> {
  return AdapterFactory.create({
    backend: StorageBackend.OPFS,
    name,
  });
}

/**
 * Create an IndexedDB-backed database (browsers)
 */
export async function createIndexedDBAdapter(
  name: string
): Promise<SQLiteAdapter> {
  return AdapterFactory.create({
    backend: StorageBackend.IndexedDB,
    name,
  });
}
