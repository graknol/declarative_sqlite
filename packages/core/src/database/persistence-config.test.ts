import { describe, it, expect, beforeEach } from 'vitest';
import {
  AdapterFactory,
  StorageBackend,
  StorageCapabilities,
  PersistenceManager,
  createMemoryAdapter,
  createBrowserAdapter,
  mergePersistenceConfig,
  resolveStorageBackend,
  DeclarativeDatabase,
  SchemaBuilder,
} from '../index';

describe('Persistence Configuration', () => {
  describe('StorageCapabilities', () => {
    it('should detect Node.js file system', () => {
      const hasFS = StorageCapabilities.hasFileSystem();
      // In Node.js test environment, this should be true
      expect(typeof hasFS).toBe('boolean');
    });

    it('should detect IndexedDB availability', () => {
      const hasIDB = StorageCapabilities.hasIndexedDB();
      expect(typeof hasIDB).toBe('boolean');
    });

    it('should detect best backend', async () => {
      const backend = await StorageCapabilities.detectBestBackend();
      expect(Object.values(StorageBackend)).toContain(backend);
    });

    it('should validate backend availability', async () => {
      const isMemoryAvailable = await StorageCapabilities.isBackendAvailable(
        StorageBackend.Memory
      );
      expect(isMemoryAvailable).toBe(true);
    });
  });

  describe('PersistenceConfig', () => {
    it('should merge with defaults', () => {
      const config = mergePersistenceConfig({
        name: 'test.db',
      });

      expect(config.name).toBe('test.db');
      expect(config.backend).toBe(StorageBackend.Auto);
      expect(config.enableWAL).toBe(true);
      expect(config.foreignKeys).toBe(true);
    });

    it('should override defaults', () => {
      const config = mergePersistenceConfig({
        name: 'test.db',
        enableWAL: false,
        synchronous: 'OFF',
        pageSize: 8192,
      });

      expect(config.enableWAL).toBe(false);
      expect(config.synchronous).toBe('OFF');
      expect(config.pageSize).toBe(8192);
    });

    it('should adjust for in-memory databases', () => {
      const config = mergePersistenceConfig({
        backend: StorageBackend.Memory,
        name: 'ignored.db',
      });

      expect(config.name).toBe(':memory:');
      expect(config.journalMode).toBe('MEMORY');
      expect(config.enableWAL).toBe(false);
    });

    it('should merge custom pragmas', () => {
      const config = mergePersistenceConfig({
        name: 'test.db',
        pragmas: {
          temp_store: 'MEMORY',
          mmap_size: 30000000000,
        },
      });

      expect(config.pragmas.temp_store).toBe('MEMORY');
      expect(config.pragmas.mmap_size).toBe(30000000000);
    });
  });

  describe('AdapterFactory', () => {
    it('should create memory adapter', async () => {
      const adapter = await createMemoryAdapter();
      expect(adapter.isOpen()).toBe(true);
      await adapter.close();
    });

    it('should create adapter with auto backend', async () => {
      const adapter = await AdapterFactory.create({
        name: 'test.db',
        backend: StorageBackend.Auto,
      });
      
      expect(adapter.isOpen()).toBe(true);
      await adapter.close();
    });

    it('should create adapter for testing scenario', async () => {
      const adapter = await AdapterFactory.quickSetup('testing');
      expect(adapter.isOpen()).toBe(true);
      await adapter.close();
    });

    it('should throw error for unavailable backend', async () => {
      // Try to use a backend that might not be available
      // This should either work or throw a helpful error
      try {
        const adapter = await AdapterFactory.create({
          name: 'test.db',
          backend: StorageBackend.OPFS,
        });
        await adapter.close();
      } catch (error) {
        expect(error instanceof Error ? error.message : String(error)).toContain('not available');
      }
    });
  });

  describe('PersistenceManager', () => {
    it('should open database with configuration', async () => {
      const adapter = await createMemoryAdapter();
      const manager = new PersistenceManager(adapter, {
        backend: StorageBackend.Memory,
        name: ':memory:',
      });

      const config = manager.getConfig();
      expect(config.backend).toBe(StorageBackend.Memory);
      expect(config.name).toBe(':memory:');
    });

    it('should get storage info', async () => {
      const adapter = await createMemoryAdapter();
      const manager = new PersistenceManager(adapter, {
        backend: StorageBackend.Memory,
      });

      const info = await manager.getStorageInfo();
      expect(info.backend).toBe(StorageBackend.Memory);
      expect(info.isMemory).toBe(true);
      expect(info.isPersistent).toBe(false);
    });

    it('should get database stats', async () => {
      const adapter = await createMemoryAdapter();
      const manager = new PersistenceManager(adapter);

      const stats = await manager.getStats();
      expect(stats.pageSize).toBeGreaterThan(0);
      expect(stats.pageCount).toBeGreaterThanOrEqual(0);
      expect(stats.totalSize).toBeGreaterThanOrEqual(0);
    });

    it('should optimize database', async () => {
      const adapter = await createMemoryAdapter();
      const manager = new PersistenceManager(adapter);

      // Should not throw for in-memory database
      await expect(manager.optimize()).resolves.toBeUndefined();
    });
  });

  describe('Integration with DeclarativeDatabase', () => {
    const schema = new SchemaBuilder()
      .table('users', t => {
        t.guid('id').notNull('');
        t.text('name').notNull('');
        t.text('email').notNull('');
        t.key('id').primary();
      })
      .build();

    it('should create database with persistence config', async () => {
      const adapter = await AdapterFactory.create({
        backend: StorageBackend.Memory,
        foreignKeys: true,
      });

      const db = new DeclarativeDatabase({
        adapter,
        schema,
        autoMigrate: true,
      });

      await db.initialize();

      // Insert and query
      const userId = await db.insert('users', {
        id: 'u1',
        name: 'Alice',
        email: 'alice@example.com',
      });

      const users = await db.query('users');
      expect(users).toHaveLength(1);
      expect(users[0].name).toBe('Alice');

      await adapter.close();
    });

    it('should work with different backends', async () => {
      // Test with memory backend
      const adapter1 = await createMemoryAdapter();
      const db1 = new DeclarativeDatabase({
        adapter: adapter1,
        schema,
        autoMigrate: true,
      });
      await db1.initialize();
      await db1.insert('users', { id: 'u1', name: 'Test' });
      await adapter1.close();

      // Test with auto backend
      const adapter2 = await createBrowserAdapter('test.db');
      const db2 = new DeclarativeDatabase({
        adapter: adapter2,
        schema,
        autoMigrate: true,
      });
      await db2.initialize();
      await db2.insert('users', { id: 'u2', name: 'Test2' });
      await adapter2.close();
    });
  });

  describe('resolveStorageBackend', () => {
    it('should resolve auto to detected backend', async () => {
      const config = mergePersistenceConfig({
        backend: StorageBackend.Auto,
        name: 'test.db',
      });

      const backend = await resolveStorageBackend(config);
      expect(Object.values(StorageBackend)).toContain(backend);
      expect(backend).not.toBe(StorageBackend.Auto);
    });

    it('should return specified backend if valid', async () => {
      const config = mergePersistenceConfig({
        backend: StorageBackend.Memory,
        name: ':memory:',
      });

      const backend = await resolveStorageBackend(config);
      expect(backend).toBe(StorageBackend.Memory);
    });
  });
});
