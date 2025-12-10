# SQLite Persistence Configuration

This guide explains how to configure persistence for the SQLite backend in declarative-sqlite.

## Table of Contents

- [Overview](#overview)
- [Storage Backends](#storage-backends)
- [Quick Start](#quick-start)
- [Configuration Options](#configuration-options)
- [Examples](#examples)
- [Advanced Usage](#advanced-usage)

## Overview

Declarative-sqlite supports multiple storage backends for different environments:

- **Memory**: In-memory database (no persistence)
- **FileSystem**: File-based storage (Node.js)
- **OPFS**: Origin Private File System (modern browsers)
- **IndexedDB**: IndexedDB-backed storage (browsers)
- **Auto**: Automatic detection of best available backend

## Storage Backends

### Memory (No Persistence)

Best for: Testing, temporary data

```typescript
import { createMemoryAdapter, DeclarativeDatabase } from 'declarative-sqlite';

const adapter = await createMemoryAdapter();
const db = new DeclarativeDatabase({ adapter, schema });
```

### FileSystem (Node.js)

Best for: Node.js applications, desktop apps

```typescript
import { createFileAdapter } from 'declarative-sqlite';

const adapter = await createFileAdapter('./myapp.db');
const db = new DeclarativeDatabase({ adapter, schema });
```

### OPFS (Modern Browsers)

Best for: PWAs, modern web apps with persistent storage

```typescript
import { createOPFSAdapter } from 'declarative-sqlite';

const adapter = await createOPFSAdapter('myapp.db');
const db = new DeclarativeDatabase({ adapter, schema });
```

### IndexedDB (Browsers)

Best for: Broader browser compatibility

```typescript
import { createIndexedDBAdapter } from 'declarative-sqlite';

const adapter = await createIndexedDBAdapter('myapp');
const db = new DeclarativeDatabase({ adapter, schema });
```

### Auto-Detection

Best for: Cross-platform apps, maximum compatibility

```typescript
import { createBrowserAdapter } from 'declarative-sqlite';

// Automatically uses OPFS if available, falls back to IndexedDB, then memory
const adapter = await createBrowserAdapter('myapp.db');
const db = new DeclarativeDatabase({ adapter, schema });
```

## Quick Start

### Using AdapterFactory

The simplest way to create a configured adapter:

```typescript
import { AdapterFactory } from 'declarative-sqlite';

// Scenario-based quick setup
const adapter = await AdapterFactory.quickSetup('browser'); // or 'node' or 'testing'

// Custom configuration
const adapter = await AdapterFactory.create({
  backend: StorageBackend.Auto,
  name: 'myapp.db',
  enableWAL: true,
  synchronous: 'NORMAL',
});
```

### Manual Configuration

For more control:

```typescript
import { 
  BetterSqlite3Adapter,
  PersistenceManager,
  StorageBackend 
} from 'declarative-sqlite';
import Database from 'better-sqlite3';

const adapter = new BetterSqlite3Adapter(Database);
const manager = new PersistenceManager(adapter, {
  backend: StorageBackend.FileSystem,
  name: './myapp.db',
  enableWAL: true,
  pageSize: 4096,
  cacheSize: -2000,
  synchronous: 'NORMAL',
});

await manager.open();
```

## Configuration Options

### PersistenceConfig Interface

```typescript
interface PersistenceConfig {
  // Storage backend to use
  backend?: StorageBackend;
  
  // Database name/path
  name: string;
  
  // Enable Write-Ahead Logging (WAL) mode
  enableWAL?: boolean; // default: true
  
  // Enable auto-vacuum to reclaim space
  autoVacuum?: boolean; // default: false
  
  // Journal mode for transactions
  journalMode?: 'DELETE' | 'TRUNCATE' | 'PERSIST' | 'MEMORY' | 'WAL' | 'OFF';
  
  // Page size in bytes
  pageSize?: number; // default: 4096
  
  // Cache size (in pages, negative = KB)
  cacheSize?: number; // default: -2000 (2MB)
  
  // Synchronous mode
  synchronous?: 'OFF' | 'NORMAL' | 'FULL' | 'EXTRA'; // default: 'NORMAL'
  
  // Enable foreign key constraints
  foreignKeys?: boolean; // default: true
  
  // Additional PRAGMA statements
  pragmas?: Record<string, string | number>;
}
```

## Examples

### Basic Browser App

```typescript
import { 
  SchemaBuilder,
  DeclarativeDatabase,
  AdapterFactory,
  StorageBackend 
} from 'declarative-sqlite';

// Define schema
const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('');
    t.text('email').notNull('');
    t.key('id').primary();
  })
  .build();

// Create adapter with persistence
const adapter = await AdapterFactory.create({
  backend: StorageBackend.Auto, // Auto-detect best backend
  name: 'myapp.db',
  enableWAL: true,
});

// Create database
const db = new DeclarativeDatabase({
  adapter,
  schema,
  autoMigrate: true,
});

await db.initialize();
```

### Node.js Application

```typescript
import { createFileAdapter, DeclarativeDatabase } from 'declarative-sqlite';

// Create file-based adapter
const adapter = await createFileAdapter('./data/myapp.db');

const db = new DeclarativeDatabase({
  adapter,
  schema,
  autoMigrate: true,
});

await db.initialize();

// Use database...
await db.insert('users', { id: 'u1', name: 'Alice', email: 'alice@example.com' });
```

### Progressive Web App (PWA)

```typescript
import { 
  createOPFSAdapter,
  DeclarativeDatabase,
  StorageCapabilities 
} from 'declarative-sqlite';

// Check if OPFS is available
const hasOPFS = await StorageCapabilities.hasOPFS();
console.log('OPFS available:', hasOPFS);

// Create OPFS adapter (falls back gracefully)
const adapter = await createOPFSAdapter('pwa-app.db');

const db = new DeclarativeDatabase({
  adapter,
  schema,
  autoMigrate: true,
});

await db.initialize();
```

### Testing with In-Memory Database

```typescript
import { createMemoryAdapter } from 'declarative-sqlite';
import { describe, it, beforeEach } from 'vitest';

describe('User Service', () => {
  let db: DeclarativeDatabase;
  
  beforeEach(async () => {
    const adapter = await createMemoryAdapter();
    db = new DeclarativeDatabase({
      adapter,
      schema,
      autoMigrate: true,
    });
    await db.initialize();
  });
  
  it('should create user', async () => {
    await db.insert('users', { id: 'u1', name: 'Test User' });
    const users = await db.query('users');
    expect(users).toHaveLength(1);
  });
});
```

## Advanced Usage

### Custom PRAGMA Configuration

```typescript
const adapter = await AdapterFactory.create({
  backend: StorageBackend.FileSystem,
  name: 'myapp.db',
  enableWAL: true,
  pageSize: 8192, // Larger page size for better performance
  cacheSize: -4000, // 4MB cache
  synchronous: 'NORMAL',
  pragmas: {
    // Additional custom PRAGMAs
    'temp_store': 'MEMORY',
    'mmap_size': 30000000000, // 30GB memory-mapped I/O
    'locking_mode': 'NORMAL',
  },
});
```

### Database Optimization

```typescript
import { PersistenceManager } from 'declarative-sqlite';

const manager = new PersistenceManager(adapter, config);
await manager.open();

// Optimize database (VACUUM + ANALYZE)
await manager.optimize();

// Checkpoint WAL file
await manager.checkpoint('PASSIVE');

// Get database statistics
const stats = await manager.getStats();
console.log('Database size:', stats.totalSize, 'bytes');
console.log('Free pages:', stats.freePages);
```

### Storage Backend Detection

```typescript
import { StorageCapabilities, StorageBackend } from 'declarative-sqlite';

// Check individual capabilities
const hasOPFS = await StorageCapabilities.hasOPFS();
const hasIndexedDB = StorageCapabilities.hasIndexedDB();
const hasFileSystem = StorageCapabilities.hasFileSystem();

console.log('Available backends:', {
  opfs: hasOPFS,
  indexeddb: hasIndexedDB,
  filesystem: hasFileSystem,
});

// Detect best backend
const bestBackend = await StorageCapabilities.detectBestBackend();
console.log('Best backend:', bestBackend);

// Validate specific backend
const isAvailable = await StorageCapabilities.isBackendAvailable(
  StorageBackend.OPFS
);
```

### Getting Storage Information

```typescript
const manager = new PersistenceManager(adapter, config);
await manager.open();

const info = await manager.getStorageInfo();
console.log('Backend:', info.backend);
console.log('Path:', info.path);
console.log('Is persistent:', info.isPersistent);
```

### Migration from In-Memory to Persistent

```typescript
// Start with in-memory for testing
let adapter = await createMemoryAdapter();
let db = new DeclarativeDatabase({ adapter, schema });
await db.initialize();

// ... do work ...

// Later, migrate to persistent storage
await adapter.close();
adapter = await createOPFSAdapter('myapp.db');
db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
await db.initialize();
```

## Performance Tips

### WAL Mode

Enable WAL mode for better concurrency:

```typescript
const adapter = await AdapterFactory.create({
  name: 'myapp.db',
  enableWAL: true, // Recommended for most use cases
  synchronous: 'NORMAL', // Good balance
});
```

### Cache Size

Adjust cache size based on available memory:

```typescript
// Small devices
cacheSize: -1000, // 1MB

// Desktop/server
cacheSize: -10000, // 10MB

// High-performance server
cacheSize: -100000, // 100MB
```

### Synchronous Mode

Trade-off between safety and performance:

```typescript
// Maximum safety (slowest)
synchronous: 'FULL',

// Balanced (recommended)
synchronous: 'NORMAL',

// Maximum performance (risk on crash)
synchronous: 'OFF',
```

## Browser Compatibility

| Backend | Chrome | Firefox | Safari | Edge |
|---------|--------|---------|--------|------|
| OPFS | ✅ 102+ | ✅ 111+ | ✅ 15.2+ | ✅ 102+ |
| IndexedDB | ✅ All | ✅ All | ✅ All | ✅ All |
| Memory | ✅ All | ✅ All | ✅ All | ✅ All |

## Troubleshooting

### OPFS Not Available

```typescript
const adapter = await AdapterFactory.create({
  backend: StorageBackend.Auto, // Falls back automatically
  name: 'myapp.db',
});

const info = await manager.getStorageInfo();
if (info.backend === StorageBackend.IndexedDB) {
  console.warn('OPFS not available, using IndexedDB');
}
```

### Storage Quota Exceeded

```typescript
// Request persistent storage
if (navigator.storage && navigator.storage.persist) {
  const isPersisted = await navigator.storage.persist();
  console.log('Persistent storage:', isPersisted);
}

// Check quota
if (navigator.storage && navigator.storage.estimate) {
  const estimate = await navigator.storage.estimate();
  console.log('Storage used:', estimate.usage);
  console.log('Storage quota:', estimate.quota);
}
```
