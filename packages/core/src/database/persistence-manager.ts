import { SQLiteAdapter } from '../adapters/adapter.interface';
import {
  PersistenceConfig,
  mergePersistenceConfig,
  configToDatabasePath,
  resolveStorageBackend,
  StorageBackend,
} from './persistence-config';

/**
 * Manages persistence configuration and initialization for SQLite adapters
 */
export class PersistenceManager {
  private config: Required<PersistenceConfig>;
  private adapter: SQLiteAdapter;
  
  constructor(adapter: SQLiteAdapter, config?: Partial<PersistenceConfig>) {
    this.adapter = adapter;
    this.config = mergePersistenceConfig(config);
  }
  
  /**
   * Open the database with persistence configuration applied
   */
  async open(): Promise<void> {
    // Resolve database path based on backend
    const path = await configToDatabasePath(this.config);
    const backend = await resolveStorageBackend(this.config);
    
    // Open the database
    await this.adapter.open(path);
    
    // Apply PRAGMA configurations
    await this.applyPragmas(backend);
  }
  
  /**
   * Apply PRAGMA settings to the database
   */
  private async applyPragmas(backend: StorageBackend): Promise<void> {
    // Don't apply certain PRAGMAs to in-memory databases
    const isMemory = backend === StorageBackend.Memory;
    
    // Journal mode
    if (this.config.journalMode) {
      await this.setPragma('journal_mode', this.config.journalMode);
    } else if (this.config.enableWAL && !isMemory) {
      await this.setPragma('journal_mode', 'WAL');
    }
    
    // Auto vacuum
    if (this.config.autoVacuum && !isMemory) {
      await this.setPragma('auto_vacuum', 'FULL');
    }
    
    // Page size (must be set before first write)
    if (this.config.pageSize !== 4096) {
      await this.setPragma('page_size', this.config.pageSize);
    }
    
    // Cache size
    await this.setPragma('cache_size', this.config.cacheSize);
    
    // Synchronous mode
    await this.setPragma('synchronous', this.config.synchronous);
    
    // Foreign keys
    await this.setPragma('foreign_keys', this.config.foreignKeys ? 'ON' : 'OFF');
    
    // Custom pragmas
    for (const [key, value] of Object.entries(this.config.pragmas)) {
      await this.setPragma(key, value);
    }
  }
  
  /**
   * Set a PRAGMA value
   */
  private async setPragma(key: string, value: string | number | boolean): Promise<void> {
    try {
      let sqlValue: string;
      
      if (typeof value === 'boolean') {
        sqlValue = value ? 'ON' : 'OFF';
      } else if (typeof value === 'number') {
        sqlValue = value.toString();
      } else {
        sqlValue = value;
      }
      
      await this.adapter.exec(`PRAGMA ${key} = ${sqlValue}`);
    } catch (error) {
      console.warn(`Failed to set PRAGMA ${key}:`, error);
    }
  }
  
  /**
   * Get current persistence configuration
   */
  getConfig(): Required<PersistenceConfig> {
    return { ...this.config };
  }
  
  /**
   * Get information about the current storage backend
   */
  async getStorageInfo(): Promise<{
    backend: StorageBackend;
    path: string;
    isMemory: boolean;
    isPersistent: boolean;
  }> {
    const backend = await resolveStorageBackend(this.config);
    const path = await configToDatabasePath(this.config);
    const isMemory = backend === StorageBackend.Memory;
    
    return {
      backend,
      path,
      isMemory,
      isPersistent: !isMemory,
    };
  }
  
  /**
   * Optimize the database (vacuum, analyze)
   */
  async optimize(): Promise<void> {
    const info = await this.getStorageInfo();
    
    if (info.isMemory) {
      // No need to optimize in-memory databases
      return;
    }
    
    try {
      // Run VACUUM if not in WAL mode or if WAL checkpoint is safe
      if (this.config.journalMode !== 'WAL') {
        await this.adapter.exec('VACUUM');
      }
      
      // Update query planner statistics
      await this.adapter.exec('ANALYZE');
    } catch (error) {
      console.warn('Database optimization failed:', error);
    }
  }
  
  /**
   * Checkpoint WAL file (for WAL mode databases)
   */
  async checkpoint(mode: 'PASSIVE' | 'FULL' | 'RESTART' | 'TRUNCATE' = 'PASSIVE'): Promise<void> {
    const info = await this.getStorageInfo();
    
    if (info.isMemory || this.config.journalMode !== 'WAL') {
      return;
    }
    
    try {
      await this.adapter.exec(`PRAGMA wal_checkpoint(${mode})`);
    } catch (error) {
      console.warn('WAL checkpoint failed:', error);
    }
  }
  
  /**
   * Get database statistics
   */
  async getStats(): Promise<{
    pageSize: number;
    pageCount: number;
    totalSize: number;
    freePages: number;
    walSize?: number;
  }> {
    const getPageSize = this.adapter.prepare('PRAGMA page_size');
    const getPageCount = this.adapter.prepare('PRAGMA page_count');
    const getFreePages = this.adapter.prepare('PRAGMA freelist_count');
    
    const pageSizeResult = await getPageSize.get<{ page_size: number }>();
    const pageCountResult = await getPageCount.get<{ page_count: number }>();
    const freePagesResult = await getFreePages.get<{ freelist_count: number }>();
    
    const pageSize = pageSizeResult?.page_size || this.config.pageSize;
    const pageCount = pageCountResult?.page_count || 0;
    const freePages = freePagesResult?.freelist_count || 0;
    
    await getPageSize.finalize();
    await getPageCount.finalize();
    await getFreePages.finalize();
    
    const stats = {
      pageSize,
      pageCount,
      totalSize: pageSize * pageCount,
      freePages,
    };
    
    // Get WAL size if in WAL mode
    if (this.config.journalMode === 'WAL') {
      try {
        const getWalSize = this.adapter.prepare('PRAGMA wal_autocheckpoint');
        await getWalSize.finalize();
      } catch {
        // WAL might not be available
      }
    }
    
    return stats;
  }
}
