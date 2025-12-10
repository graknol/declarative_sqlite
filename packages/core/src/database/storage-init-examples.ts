/**
 * Example: Proper storage initialization with permission requests
 */

import {
  initializeStorage,
  checkStorageAvailability,
  AdapterFactory,
  DeclarativeDatabase,
  SchemaBuilder,
  StorageBackend,
} from '../index';

// Extend ImportMeta to include env for Vite/bundler environments
declare global {
  interface ImportMeta {
    env?: {
      DEV?: boolean;
      [key: string]: any;
    };
  }
}

const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('');
    t.text('email').notNull('');
    t.key('id').primary();
  })
  .build();

/**
 * Example 1: Full initialization with all checks
 */
export async function fullInitializationExample() {
  console.log('=== Full Storage Initialization ===\n');
  
  // Step 1: Check storage availability
  const storageCheck = await checkStorageAvailability(10 * 1024 * 1024); // 10MB
  console.log('Storage Check:');
  console.log('  Available:', storageCheck.available);
  console.log('  Has space for 10MB:', storageCheck.hasSpace);
  console.log('  Usage:', (storageCheck.usage / 1024 / 1024).toFixed(2), 'MB');
  console.log('  Quota:', (storageCheck.quota / 1024 / 1024).toFixed(2), 'MB');
  console.log('  Remaining:', (storageCheck.remaining / 1024 / 1024).toFixed(2), 'MB');
  
  if (!storageCheck.hasSpace) {
    throw new Error('Not enough storage space available');
  }
  
  // Step 2: Initialize storage with permission requests
  const storageInit = await initializeStorage({
    requestPersistence: true,
    preferredBackend: StorageBackend.OPFS,
    verbose: true,
  });
  
  console.log('\nStorage Initialization Result:');
  console.log('  Backend:', storageInit.backend);
  console.log('  Persistent:', storageInit.isPersistent);
  
  if (storageInit.quota) {
    console.log('  Quota usage:', storageInit.quota.percentUsed.toFixed(1), '%');
  }
  
  if (storageInit.warnings.length > 0) {
    console.warn('\nWarnings:');
    storageInit.warnings.forEach(w => console.warn('  -', w));
  }
  
  // Step 3: Create adapter with detected backend
  const adapter = await AdapterFactory.create({
    backend: storageInit.backend,
    name: 'myapp.db',
    enableWAL: true,
  });
  
  // Step 4: Create and use database
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  await db.insert('users', {
    id: 'u1',
    name: 'Alice',
    email: 'alice@example.com',
  });
  
  const users = await db.query('users');
  console.log('\nUsers:', users);
  
  await db.close();
}

/**
 * Example 2: Quick initialization for PWA
 */
export async function pwaInitializationExample() {
  console.log('=== PWA Initialization ===\n');
  
  // Quick initialization with sensible defaults
  const result = await initializeStorage({
    requestPersistence: true, // Always request for PWAs
    preferredBackend: StorageBackend.Auto, // Auto-detect
  });
  
  if (!result.isPersistent) {
    // Warn user that data might be evicted
    console.warn('⚠️ Persistent storage not granted. Data may be cleared by the browser.');
    
    // In a real app, you might show a UI notification
    // showNotification('For best experience, please grant persistent storage permission');
  }
  
  const adapter = await AdapterFactory.create({
    backend: result.backend,
    name: 'pwa-app.db',
    enableWAL: true,
    synchronous: 'NORMAL',
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  console.log('PWA database ready with backend:', result.backend);
  
  await db.close();
}

/**
 * Example 3: Graceful degradation
 */
export async function gracefulDegradationExample() {
  console.log('=== Graceful Degradation Example ===\n');
  
  const result = await initializeStorage({
    preferredBackend: StorageBackend.OPFS,
    requestPersistence: true,
    verbose: true,
  });
  
  // Handle different backends
  switch (result.backend) {
    case StorageBackend.OPFS:
      console.log('✅ Using OPFS - best performance and persistence');
      break;
    
    case StorageBackend.IndexedDB:
      console.log('⚠️ Using IndexedDB - OPFS not available');
      console.log('   Performance may be slightly reduced');
      break;
    
    case StorageBackend.Memory:
      console.log('❌ Using in-memory storage - NO PERSISTENCE');
      console.log('   Data will be lost on page reload');
      
      // In a real app, show a prominent warning to the user
      const confirmProceed = confirm(
        'Storage is not available. Your data will not be saved. Continue anyway?'
      );
      
      if (!confirmProceed) {
        throw new Error('User cancelled due to lack of persistent storage');
      }
      break;
  }
  
  const adapter = await AdapterFactory.create({
    backend: result.backend,
    name: 'myapp.db',
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  await db.close();
}

/**
 * Example 4: Handle quota exceeded errors
 */
export async function quotaHandlingExample() {
  console.log('=== Quota Handling Example ===\n');
  
  const result = await initializeStorage({
    requestPersistence: true,
  });
  
  if (result.quota && result.quota.percentUsed > 90) {
    console.error('Storage is critically low!');
    console.error('Consider cleaning up old data or requesting more storage');
    
    // In a real app, you might:
    // 1. Clean up old data
    // 2. Show UI to let user delete data
    // 3. Compress or archive old records
  }
  
  const adapter = await AdapterFactory.create({
    backend: result.backend,
    name: 'myapp.db',
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  try {
    // Try to insert data
    await db.insert('users', {
      id: 'u1',
      name: 'Test',
      email: 'test@example.com',
    });
  } catch (error) {
    if (error instanceof Error && (error.message?.includes('quota') || error.name === 'QuotaExceededError')) {
      console.error('Storage quota exceeded!');
      
      // Handle quota exceeded:
      // 1. Clean up old data
      // 2. Notify user
      // 3. Disable features that create data
    } else {
      throw error;
    }
  }
  
  await db.close();
}

/**
 * Example 5: React/Vue component integration
 */
export async function componentIntegrationExample() {
  console.log('=== Component Integration Example ===\n');
  
  // This could be in a React useEffect or Vue onMounted
  async function initializeApp() {
    const result = await initializeStorage({
      requestPersistence: true,
      preferredBackend: StorageBackend.Auto,
      verbose: import.meta.env?.DEV ?? false, // Only verbose in development
    });
    
    // Store initialization result in app state
    const appState = {
      storageBackend: result.backend,
      isPersistent: result.isPersistent,
      warnings: result.warnings,
    };
    
    // Show warnings to user if needed
    if (!result.isPersistent) {
      // setWarningMessage('Your data may not be preserved between sessions');
    }
    
    // Create database
    const adapter = await AdapterFactory.create({
      backend: result.backend,
      name: 'app.db',
    });
    
    const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
    await db.initialize();
    
    return { db, appState };
  }
  
  const { db, appState } = await initializeApp();
  console.log('App initialized:', appState);
  
  await db.close();
}

/**
 * Run all examples
 */
export async function runAllInitExamples() {
  try {
    await fullInitializationExample();
    console.log('\n---\n');
    
    await pwaInitializationExample();
    console.log('\n---\n');
    
    await gracefulDegradationExample();
    console.log('\n---\n');
    
    await quotaHandlingExample();
    console.log('\n---\n');
    
    await componentIntegrationExample();
    
    console.log('\n=== All initialization examples completed ===');
  } catch (error) {
    console.error('Example failed:', error);
  }
}

// Run if executed directly
if (require.main === module) {
  runAllInitExamples().catch(console.error);
}
