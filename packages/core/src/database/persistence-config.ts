/**
 * Persistence configuration for SQLite database backends
 * Supports multiple storage backends for different environments
 */

/**
 * Storage backend types for SQLite persistence
 */
export enum StorageBackend {
  /** In-memory database (no persistence) */
  Memory = 'memory',
  
  /** File system (sqlite-wasm with file VFS) */
  FileSystem = 'filesystem',
  
  /** Origin Private File System (modern browsers) */
  OPFS = 'opfs',
  
  /** IndexedDB-backed storage (browsers) */
  IndexedDB = 'indexeddb',
  
  /** Auto-detect best available backend */
  Auto = 'auto',
}

/**
 * Configuration for persistent SQLite storage
 */
export interface PersistenceConfig {
  /**
   * Storage backend to use
   * @default StorageBackend.Auto
   */
  backend?: StorageBackend;
  
  /**
   * Database name/path
   * - For FileSystem: file path (e.g., 'myapp.db', '/data/myapp.db')
   * - For OPFS: database name (e.g., 'myapp.db')
   * - For IndexedDB: database name (e.g., 'myapp')
   * - For Memory: ignored (uses ':memory:')
   */
  name: string;
  
  /**
   * Enable Write-Ahead Logging (WAL) mode
   * Improves concurrency and performance
   * @default true
   */
  enableWAL?: boolean;
  
  /**
   * Enable auto-vacuum to reclaim space
   * @default false
   */
  autoVacuum?: boolean;
  
  /**
   * Journal mode for transactions
   * @default 'WAL' (or 'DELETE' for in-memory)
   */
  journalMode?: 'DELETE' | 'TRUNCATE' | 'PERSIST' | 'MEMORY' | 'WAL' | 'OFF';
  
  /**
   * Page size in bytes
   * @default 4096
   */
  pageSize?: number;
  
  /**
   * Cache size (in pages)
   * @default -2000 (2MB)
   */
  cacheSize?: number;
  
  /**
   * Synchronous mode (trade-off between speed and durability)
   * - FULL: Maximum durability, slower
   * - NORMAL: Good balance (default)
   * - OFF: Fastest, risk of corruption on crash
   * @default 'NORMAL'
   */
  synchronous?: 'OFF' | 'NORMAL' | 'FULL' | 'EXTRA';
  
  /**
   * Enable foreign key constraints
   * @default true
   */
  foreignKeys?: boolean;
  
  /**
   * Additional PRAGMA statements to execute on open
   */
  pragmas?: Record<string, string | number>;
}

/**
 * Default persistence configuration
 */
export const DEFAULT_PERSISTENCE_CONFIG: Required<PersistenceConfig> = {
  backend: StorageBackend.Auto,
  name: ':memory:',
  enableWAL: true,
  autoVacuum: false,
  journalMode: 'WAL',
  pageSize: 4096,
  cacheSize: -2000,
  synchronous: 'NORMAL',
  foreignKeys: true,
  pragmas: {},
};

/**
 * Merge user config with defaults
 */
export function mergePersistenceConfig(
  config?: Partial<PersistenceConfig>
): Required<PersistenceConfig> {
  if (!config) {
    return DEFAULT_PERSISTENCE_CONFIG;
  }
  
  const merged = {
    ...DEFAULT_PERSISTENCE_CONFIG,
    ...config,
    pragmas: {
      ...DEFAULT_PERSISTENCE_CONFIG.pragmas,
      ...(config.pragmas || {}),
    },
  };
  
  // Adjust defaults for in-memory databases
  if (merged.backend === StorageBackend.Memory) {
    merged.name = ':memory:';
    merged.journalMode = 'MEMORY';
    merged.enableWAL = false;
  }
  
  return merged;
}

/**
 * Capability detection for storage backends
 */
export class StorageCapabilities {
  /**
   * Check if OPFS (Origin Private File System) is available
   */
  static async hasOPFS(): Promise<boolean> {
    if (typeof navigator === 'undefined' || !navigator.storage) {
      return false;
    }
    
    try {
      // Check for OPFS API
      return 'getDirectory' in navigator.storage;
    } catch {
      return false;
    }
  }
  
  /**
   * Check if IndexedDB is available
   */
  static hasIndexedDB(): boolean {
    return typeof indexedDB !== 'undefined';
  }
  
  /**
   * Check if file system access is available (Node.js)
   */
  static hasFileSystem(): boolean {
    return typeof process !== 'undefined' && process.versions?.node !== undefined;
  }
  
  /**
   * Detect the best available storage backend
   */
  static async detectBestBackend(): Promise<StorageBackend> {
    // Node.js environment
    if (this.hasFileSystem()) {
      return StorageBackend.FileSystem;
    }
    
    // Modern browsers with OPFS
    if (await this.hasOPFS()) {
      return StorageBackend.OPFS;
    }
    
    // Fallback to IndexedDB
    if (this.hasIndexedDB()) {
      return StorageBackend.IndexedDB;
    }
    
    // Last resort: in-memory
    return StorageBackend.Memory;
  }
  
  /**
   * Validate if a backend is available
   */
  static async isBackendAvailable(backend: StorageBackend): Promise<boolean> {
    switch (backend) {
      case StorageBackend.Memory:
        return true;
      case StorageBackend.FileSystem:
        return this.hasFileSystem();
      case StorageBackend.OPFS:
        return await this.hasOPFS();
      case StorageBackend.IndexedDB:
        return this.hasIndexedDB();
      case StorageBackend.Auto:
        return true;
      default:
        return false;
    }
  }
}

/**
 * Helper to resolve the actual backend from config
 */
export async function resolveStorageBackend(
  config: Required<PersistenceConfig>
): Promise<StorageBackend> {
  if (config.backend === StorageBackend.Auto) {
    return await StorageCapabilities.detectBestBackend();
  }
  
  const isAvailable = await StorageCapabilities.isBackendAvailable(config.backend);
  if (!isAvailable) {
    throw new Error(
      `Storage backend '${config.backend}' is not available in this environment. ` +
      `Consider using StorageBackend.Auto for automatic detection.`
    );
  }
  
  return config.backend;
}

/**
 * Convert persistence config to database path for adapter
 */
export async function configToDatabasePath(
  config: Required<PersistenceConfig>
): Promise<string> {
  const backend = await resolveStorageBackend(config);
  
  switch (backend) {
    case StorageBackend.Memory:
      return ':memory:';
    
    case StorageBackend.FileSystem:
      return config.name;
    
    case StorageBackend.OPFS:
      // OPFS path format for sqlite-wasm
      return `/opfs/${config.name}`;
    
    case StorageBackend.IndexedDB:
      // IndexedDB path format (custom scheme)
      return `indexeddb://${config.name}`;
    
    default:
      throw new Error(`Unsupported storage backend: ${backend}`);
  }
}
