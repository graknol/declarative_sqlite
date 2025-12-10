/**
 * Examples demonstrating SQLite persistence configuration
 * 
 * Run these examples to see how different storage backends work
 */

import {
  SchemaBuilder,
  DeclarativeDatabase,
  AdapterFactory,
  StorageBackend,
  PersistenceManager,
  StorageCapabilities,
  createMemoryAdapter,
  createFileAdapter,
  createBrowserAdapter,
} from '../index';

// Define a simple schema for examples
const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('');
    t.text('email').notNull('');
    t.integer('age').notNull(0);
    t.key('id').primary();
  })
  .build();

/**
 * Example 1: Auto-detect best storage backend
 */
export async function example1_AutoDetect() {
  console.log('Example 1: Auto-detect best storage backend');
  
  const adapter = await AdapterFactory.create({
    name: 'myapp.db',
    backend: StorageBackend.Auto,
  });
  
  const manager = new PersistenceManager(adapter);
  const info = await manager.getStorageInfo();
  
  console.log('Selected backend:', info.backend);
  console.log('Database path:', info.path);
  console.log('Is persistent:', info.isPersistent);
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  await db.insert('users', {
    id: 'u1',
    name: 'Alice',
    email: 'alice@example.com',
    age: 30,
  });
  
  const users = await db.query('users');
  console.log('Users:', users);
  
  await adapter.close();
}

/**
 * Example 2: In-memory database for testing
 */
export async function example2_InMemory() {
  console.log('Example 2: In-memory database');
  
  const adapter = await createMemoryAdapter();
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  // Data only exists in memory
  await db.insert('users', { id: 'u1', name: 'Test User', email: 'test@example.com', age: 25 });
  
  const users = await db.query('users');
  console.log('In-memory users:', users);
  
  await adapter.close();
  // Data is lost after closing
}

/**
 * Example 3: File-based persistence (Node.js)
 */
export async function example3_FileSystem() {
  console.log('Example 3: File-based persistence');
  
  if (!StorageCapabilities.hasFileSystem()) {
    console.log('File system not available (browser environment)');
    return;
  }
  
  const adapter = await createFileAdapter('./example.db');
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  await db.insert('users', {
    id: 'u1',
    name: 'Persistent User',
    email: 'persistent@example.com',
    age: 35,
  });
  
  const users = await db.query('users');
  console.log('Persistent users:', users);
  
  await adapter.close();
  // Data persists to ./example.db
}

/**
 * Example 4: Browser with OPFS
 */
export async function example4_OPFS() {
  console.log('Example 4: OPFS persistence');
  
  const hasOPFS = await StorageCapabilities.hasOPFS();
  console.log('OPFS available:', hasOPFS);
  
  if (!hasOPFS) {
    console.log('OPFS not available, will fall back to IndexedDB');
  }
  
  const adapter = await AdapterFactory.create({
    name: 'myapp.db',
    backend: hasOPFS ? StorageBackend.OPFS : StorageBackend.Auto,
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  await db.insert('users', {
    id: 'u1',
    name: 'OPFS User',
    email: 'opfs@example.com',
    age: 28,
  });
  
  const users = await db.query('users');
  console.log('OPFS users:', users);
  
  await adapter.close();
}

/**
 * Example 5: Custom persistence configuration
 */
export async function example5_CustomConfig() {
  console.log('Example 5: Custom persistence configuration');
  
  const adapter = await AdapterFactory.create({
    name: 'custom.db',
    backend: StorageBackend.Auto,
    enableWAL: true,
    pageSize: 8192,
    cacheSize: -4000, // 4MB cache
    synchronous: 'NORMAL',
    foreignKeys: true,
    pragmas: {
      temp_store: 'MEMORY',
    },
  });
  
  const manager = new PersistenceManager(adapter);
  const config = manager.getConfig();
  
  console.log('Configuration:');
  console.log('  WAL enabled:', config.enableWAL);
  console.log('  Page size:', config.pageSize);
  console.log('  Cache size:', config.cacheSize);
  console.log('  Synchronous:', config.synchronous);
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  await adapter.close();
}

/**
 * Example 6: Database optimization
 */
export async function example6_Optimization() {
  console.log('Example 6: Database optimization');
  
  const adapter = await createMemoryAdapter();
  const manager = new PersistenceManager(adapter, {
    backend: StorageBackend.Memory,
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  // Insert test data
  for (let i = 1; i <= 100; i++) {
    await db.insert('users', {
      id: `u${i}`,
      name: `User ${i}`,
      email: `user${i}@example.com`,
      age: 20 + (i % 50),
    });
  }
  
  // Get database stats
  const stats = await manager.getStats();
  console.log('Database statistics:');
  console.log('  Page size:', stats.pageSize, 'bytes');
  console.log('  Page count:', stats.pageCount);
  console.log('  Total size:', stats.totalSize, 'bytes');
  console.log('  Free pages:', stats.freePages);
  
  // Optimize
  await manager.optimize();
  console.log('Database optimized (VACUUM + ANALYZE)');
  
  await adapter.close();
}

/**
 * Example 7: Quick setup scenarios
 */
export async function example7_QuickSetup() {
  console.log('Example 7: Quick setup scenarios');
  
  // Testing scenario
  console.log('\nTesting scenario:');
  const testAdapter = await AdapterFactory.quickSetup('testing');
  console.log('  Opened:', testAdapter.isOpen());
  await testAdapter.close();
  
  // Browser scenario
  console.log('\nBrowser scenario:');
  const browserAdapter = await AdapterFactory.quickSetup('browser');
  const browserInfo = await new PersistenceManager(browserAdapter).getStorageInfo();
  console.log('  Backend:', browserInfo.backend);
  await browserAdapter.close();
  
  // Node scenario (if available)
  if (StorageCapabilities.hasFileSystem()) {
    console.log('\nNode scenario:');
    const nodeAdapter = await AdapterFactory.quickSetup('node');
    console.log('  Opened:', nodeAdapter.isOpen());
    await nodeAdapter.close();
  }
}

/**
 * Example 8: Storage capability detection
 */
export async function example8_Capabilities() {
  console.log('Example 8: Storage capability detection');
  
  console.log('Capabilities:');
  console.log('  File System:', StorageCapabilities.hasFileSystem());
  console.log('  IndexedDB:', StorageCapabilities.hasIndexedDB());
  console.log('  OPFS:', await StorageCapabilities.hasOPFS());
  
  const bestBackend = await StorageCapabilities.detectBestBackend();
  console.log('\nBest backend:', bestBackend);
  
  // Check if specific backends are available
  const backends = [
    StorageBackend.Memory,
    StorageBackend.FileSystem,
    StorageBackend.OPFS,
    StorageBackend.IndexedDB,
  ];
  
  console.log('\nBackend availability:');
  for (const backend of backends) {
    const isAvailable = await StorageCapabilities.isBackendAvailable(backend);
    console.log(`  ${backend}:`, isAvailable);
  }
}

/**
 * Run all examples
 */
export async function runAllExamples() {
  console.log('=== SQLite Persistence Configuration Examples ===\n');
  
  try {
    await example1_AutoDetect();
    console.log('\n---\n');
    
    await example2_InMemory();
    console.log('\n---\n');
    
    await example3_FileSystem();
    console.log('\n---\n');
    
    await example4_OPFS();
    console.log('\n---\n');
    
    await example5_CustomConfig();
    console.log('\n---\n');
    
    await example6_Optimization();
    console.log('\n---\n');
    
    await example7_QuickSetup();
    console.log('\n---\n');
    
    await example8_Capabilities();
    
    console.log('\n=== All examples completed ===');
  } catch (error) {
    console.error('Example failed:', error);
  }
}

// Run examples if executed directly
if (require.main === module) {
  runAllExamples().catch(console.error);
}
