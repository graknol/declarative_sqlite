/**
 * Example: Exporting and downloading SQLite database
 * 
 * This demonstrates how to export the database and download it in a browser
 */

import {
  SchemaBuilder,
  DeclarativeDatabase,
  AdapterFactory,
  StorageBackend,
} from '../index';

const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('');
    t.text('email').notNull('');
    t.key('id').primary();
  })
  .build();

/**
 * Export database to a file (browser download)
 */
export async function exportDatabaseToDownload() {
  // Create and populate database
  const adapter = await AdapterFactory.create({
    backend: StorageBackend.Memory,
    name: 'myapp.db',
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  // Add some data
  await db.insert('users', { id: 'u1', name: 'Alice', email: 'alice@example.com' });
  await db.insert('users', { id: 'u2', name: 'Bob', email: 'bob@example.com' });
  
  // Export database
  const dbBytes = await db.exportDatabase();
  console.log('Database size:', dbBytes.length, 'bytes');
  
  // In browser: trigger download
  if (typeof window !== 'undefined') {
    const blob = new Blob([new Uint8Array(dbBytes)], { type: 'application/x-sqlite3' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'myapp.db';
    a.click();
    URL.revokeObjectURL(url);
    console.log('Database download triggered');
  }
  
  await db.close();
}

/**
 * Export database to file system (Node.js)
 */
export async function exportDatabaseToFile() {
  const adapter = await AdapterFactory.create({
    backend: StorageBackend.Memory,
    name: 'myapp.db',
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  // Add some data
  await db.insert('users', { id: 'u1', name: 'Alice', email: 'alice@example.com' });
  
  // Export database
  const dbBytes = await db.exportDatabase();
  
  // In Node.js: write to file
  if (typeof process !== 'undefined' && process.versions?.node) {
    const fs = await import('fs/promises');
    await fs.writeFile('exported-database.db', dbBytes);
    console.log('Database exported to exported-database.db');
  }
  
  await db.close();
}

/**
 * Create a backup of the database
 */
export async function createDatabaseBackup() {
  const adapter = await AdapterFactory.create({
    backend: StorageBackend.Auto,
    name: 'myapp.db',
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  // Regular operations...
  await db.insert('users', { id: 'u1', name: 'Alice', email: 'alice@example.com' });
  
  // Create backup
  const backup = await db.exportDatabase();
  
  // Store backup (could be to IndexedDB, localStorage, server, etc.)
  if (typeof localStorage !== 'undefined') {
    // Convert to base64 for localStorage
    const base64 = btoa(String.fromCharCode(...backup));
    localStorage.setItem('db-backup', base64);
    console.log('Backup stored in localStorage');
  }
  
  await db.close();
}

/**
 * Restore database from backup
 */
export async function restoreDatabaseFromBackup() {
  if (typeof localStorage === 'undefined') {
    console.log('localStorage not available');
    return;
  }
  
  // Retrieve backup
  const base64 = localStorage.getItem('db-backup');
  if (!base64) {
    console.log('No backup found');
    return;
  }
  
  // Convert from base64
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  
  // Note: To restore, you would need to use the database's import functionality
  // This varies by adapter - sqlite-wasm might support importing via constructor
  console.log('Backup data retrieved:', bytes.length, 'bytes');
}

/**
 * Export database periodically (auto-backup)
 */
export async function setupAutoBackup(intervalMs: number = 60000) {
  const adapter = await AdapterFactory.create({
    backend: StorageBackend.Auto,
    name: 'myapp.db',
  });
  
  const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
  await db.initialize();
  
  // Setup periodic backup
  const backupInterval = setInterval(async () => {
    try {
      const backup = await db.exportDatabase();
      const timestamp = new Date().toISOString();
      
      // Store with timestamp
      if (typeof localStorage !== 'undefined') {
        const base64 = btoa(String.fromCharCode(...backup));
        localStorage.setItem(`db-backup-${timestamp}`, base64);
        console.log(`Backup created at ${timestamp}`);
        
        // Keep only last 5 backups
        const keys = Object.keys(localStorage).filter(k => k.startsWith('db-backup-'));
        if (keys.length > 5) {
          keys.sort();
          for (let i = 0; i < keys.length - 5; i++) {
            const key = keys[i];
            if (key) localStorage.removeItem(key);
          }
        }
      }
    } catch (error) {
      console.error('Backup failed:', error);
    }
  }, intervalMs);
  
  // Return cleanup function
  return () => {
    clearInterval(backupInterval);
    db.close();
  };
}

/**
 * Compare two database exports
 */
export async function compareDatabases() {
  // Create two databases
  const adapter1 = await AdapterFactory.create({ backend: StorageBackend.Memory });
  const db1 = new DeclarativeDatabase({ adapter: adapter1, schema, autoMigrate: true });
  await db1.initialize();
  await db1.insert('users', { id: 'u1', name: 'Alice', email: 'alice@example.com' });
  
  const adapter2 = await AdapterFactory.create({ backend: StorageBackend.Memory });
  const db2 = new DeclarativeDatabase({ adapter: adapter2, schema, autoMigrate: true });
  await db2.initialize();
  await db2.insert('users', { id: 'u1', name: 'Alice', email: 'alice@example.com' });
  
  // Export both
  const export1 = await db1.exportDatabase();
  const export2 = await db2.exportDatabase();
  
  // Compare
  const areEqual = export1.length === export2.length &&
                   export1.every((byte, i) => byte === export2[i]);
  
  console.log('Databases are equal:', areEqual);
  console.log('Database 1 size:', export1.length);
  console.log('Database 2 size:', export2.length);
  
  await db1.close();
  await db2.close();
}

// Run examples if executed directly
if (require.main === module) {
  (async () => {
    console.log('=== Database Export Examples ===\n');
    
    await exportDatabaseToDownload();
    await exportDatabaseToFile();
    await createDatabaseBackup();
    await compareDatabases();
    
    console.log('\n=== Examples completed ===');
  })().catch(console.error);
}
