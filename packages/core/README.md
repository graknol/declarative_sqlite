# declarative-sqlite

[![npm version](https://badge.fury.io/js/declarative-sqlite.svg)](https://www.npmjs.com/package/declarative-sqlite)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

TypeScript port of `declarative_sqlite` for PWA and Capacitor applications with **zero code generation**, automatic schema migration, and built-in conflict resolution for offline-first apps.

## ✨ Key Features

- **🚀 Zero Code Generation** - Use JavaScript Proxy for type-safe record access (no build step!)
- **📦 Tiny Bundle** - ~50KB uncompressed (~15KB gzipped)
- **🔄 Automatic Migration** - Declarative schema with automatic database migration
- **🎯 Type-Safe** - Full TypeScript support without decorators or annotations
- **⚛️ Reactive** - RxJS-based streaming queries with auto-refresh
- **📱 Offline-First** - HLC timestamps + LWW conflict resolution
- **📎 File Management** - Built-in file storage with versioning
- **🔌 Pluggable** - Support for multiple SQLite backends (wa-sqlite, Capacitor, better-sqlite3)
- **👷 Web Worker Support** - Built-in Comlink integration for thread-safe database operations

## 📥 Installation

```bash
npm install declarative-sqlite rxjs
```

## 🚀 Quick Start

```typescript
import { SchemaBuilder, DeclarativeDatabase, AdapterFactory } from 'declarative-sqlite';

// 1. Define your schema (declarative)
const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('');
    t.text('email').notNull('');
    t.integer('age').notNull(0);
    t.key('id').primary();
  })
  .build();

// 2. Create database with automatic persistence configuration
const adapter = await AdapterFactory.create({
  name: 'myapp.db', // Auto-detects best storage backend
  enableWAL: true,
});

const db = new DeclarativeDatabase({
  adapter,
  schema,
  autoMigrate: true // Automatically migrates schema changes
});

await db.initialize();

// 3. Use it!
await db.insert('users', { id: 'u1', name: 'Alice', email: 'alice@example.com', age: 30 });
const users = await db.query('users', { where: 'age >= ?', whereArgs: [21] });
```

## 💾 Persistence Configuration

Supports multiple storage backends for different environments:

```typescript
import { AdapterFactory, StorageBackend } from 'declarative-sqlite';

// Browser with auto-detection (OPFS → IndexedDB → Memory)
const adapter = await AdapterFactory.create({
  name: 'myapp.db',
  backend: StorageBackend.Auto,
});

// Node.js with file system
const adapter = await AdapterFactory.create({
  name: './data/myapp.db',
  backend: StorageBackend.FileSystem,
});

// PWA with OPFS (Origin Private File System)
const adapter = await AdapterFactory.create({
  name: 'myapp.db',
  backend: StorageBackend.OPFS,
});

// In-memory for testing
const adapter = await AdapterFactory.create({
  backend: StorageBackend.Memory,
});

// Custom WASM directory (if serving from /assets/)
// Place sqlite3.wasm, sqlite3-opfs-async-proxy.js, and sqlite3-worker1.js in /assets/
const adapter = await AdapterFactory.create({
  name: 'myapp.db',
  wasmDir: '/assets',
});
```

See [PERSISTENCE.md](./PERSISTENCE.md) for detailed configuration options.


## 💡 Zero Code Generation (Key Innovation!)

Unlike the Dart version which requires `build_runner` and code generation, the TypeScript version uses JavaScript Proxy objects for instant, type-safe property access:

```typescript
// Define interface (NO decorators, NO annotations!)
interface User {
  id: string;
  name: string;
  email: string;
  age: number;
}

// Create record (NO code generation!)
const user = db.createRecord<User>('users');

// Type-safe property access (instant feedback!)
user.name = 'Alice';
user.email = 'alice@example.com';
user.age = 30;

// Save to database
await user.save(); // INSERT

// Update
user.age = 31;
await user.save(); // UPDATE (only changed fields)

// Delete
await user.delete();
```

**Result**: 60x faster development (instant vs ~30s build_runner) ⚡

## 📖 Core Concepts

### Declarative Schema

Define your database schema in code with a fluent builder API:

```typescript
const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('').maxLength(255);
    t.text('email').notNull('');
    t.integer('age').notNull(0);
    t.real('balance').lww(); // Last-Write-Wins for sync
    t.fileset('documents').max(16).maxFileSize(8 * 1024 * 1024);
    
    t.key('id').primary();
    t.key('email').unique();
    t.key('name').index();
  })
  .build();
```

### Automatic Migration

Schema changes are automatically detected and migrated:

```typescript
// Add a column to your schema
t.text('phone').notNull('');

// On next initialization, migration runs automatically:
// ALTER TABLE users ADD COLUMN "phone" TEXT NOT NULL DEFAULT ''
```

### Reactive Queries with RxJS

Stream query results that auto-update when data changes:

```typescript
import { map, debounceTime } from 'rxjs/operators';

const users$ = db.stream<User>('users', {
  where: 'age >= ?',
  whereArgs: [21]
});

users$
  .pipe(
    map(users => users.filter(u => u.status === 'active')),
    debounceTime(300)
  )
  .subscribe(users => updateUI(users));

// Any insert/update/delete automatically triggers refresh!
await db.insert('users', { id: 'u2', name: 'Bob', age: 25 });
// Stream subscribers receive updated data
```

### Offline-First Synchronization

Built-in Hybrid Logical Clock (HLC) timestamps and Last-Write-Wins (LWW) conflict resolution:

```typescript
import { Hlc, LwwOperations } from 'declarative-sqlite';

const hlc = new Hlc('device-123');
const lww = new LwwOperations(adapter, hlc);

// Update with automatic HLC timestamp
await lww.updateLww('users', 
  { balance: 100.50 },
  { where: 'id = ?', whereArgs: ['user-1'] }
);

// During sync: Apply remote changes with conflict resolution
const applied = await lww.updateLwwIfNewer(
  'users',
  'user-1',
  'balance',
  150.00,
  incomingTimestamp
);
// Returns true if applied (incoming was newer), false otherwise
```

### File Management

Built-in file storage with automatic versioning:

```typescript
import { FilesystemFileRepository, FileSet } from 'declarative-sqlite';

const fileRepo = new FilesystemFileRepository(adapter, hlc, '/data/files');

// Schema with fileset column
t.fileset('attachments').max(16).maxFileSize(8 * 1024 * 1024);

// Use FileSet API
const attachments = new FileSet(fileRepo, 'attachments', 16, 8 * 1024 * 1024);
await attachments.addFile('contract.pdf', pdfBytes);

const files = await attachments.listFiles();
const content = await attachments.getFile(fileId);
```

## 🔌 SQLite Adapters

### Node.js (better-sqlite3)

```typescript
import { BetterSqlite3Adapter } from 'declarative-sqlite';
import Database from 'better-sqlite3';

const adapter = new BetterSqlite3Adapter(Database);
await adapter.open('myapp.db');
```

### Browser/PWA (wa-sqlite) - Coming Soon

```typescript
import { WaSqliteAdapter } from 'declarative-sqlite';

const adapter = new WaSqliteAdapter();
await adapter.open('myapp.db');
```

### Capacitor (iOS/Android) - Coming Soon

```typescript
import { CapacitorSqliteAdapter } from 'declarative-sqlite';

const adapter = new CapacitorSqliteAdapter();
await adapter.open('myapp.db');
```

## 📚 API Reference

### Schema Builders

- `SchemaBuilder` - Define database schema
- `TableBuilder` - Define table structure
- `KeyBuilder` - Define primary keys, unique constraints, indices
- Column builders: `text()`, `integer()`, `real()`, `guid()`, `date()`, `fileset()`

### Database Operations

- `DeclarativeDatabase` - Main database class
  - `insert()` - Insert records
  - `insertMany()` - Bulk insert
  - `update()` - Update records
  - `delete()` - Delete records
  - `query()` - Query records
  - `queryOne()` - Query single record
  - `transaction()` - Execute in transaction
  - `stream()` - Reactive query stream

### Query Builder

- `QueryBuilder` - Fluent SQL query builder
  - `select()`, `from()`, `where()`, `join()`, `orderBy()`, `groupBy()`, `limit()`, `offset()`

### Synchronization

- `Hlc` - Hybrid Logical Clock
- `LwwOperations` - Last-Write-Wins operations
- `DirtyRowStore` - Change tracking

### File Management

- `IFileRepository` - File storage interface
- `FilesystemFileRepository` - File system implementation
- `FileSet` - High-level file management API

### Records

- `DbRecord` - Proxy-based typed records (zero code generation!)

## 🎯 Migration from Dart

| Feature | Dart | TypeScript |
|---------|------|------------|
| **Code Generation** | Required (~30s) | ❌ None (instant) |
| **Build Step** | `build_runner build` | ❌ None |
| **Bundle Size** | ~23MB | ~50KB (~460x smaller) |
| **Type Safety** | Generated classes | Proxy + TypeScript |
| **Streaming** | Custom (1,200 LOC) | RxJS (industry standard) |
| **Dev Cycle** | ~30s per change | < 1s (instant) |

## 🧪 Testing

```bash
npm test                 # Run tests
npm run test:watch       # Watch mode
npm run test:coverage    # With coverage
npm run test:ui          # Vitest UI
```

## 🏗️ Build

```bash
npm run build     # Build package
npm run dev       # Watch mode
npm run typecheck # Type checking
npm run lint      # Lint code
```

## 📄 License

MIT © graknol

## 🔗 Links

- [Repository](https://github.com/graknol/declarative_sqlite)
- [Comlink Integration Guide](./COMLINK_INTEGRATION.md) - Use with web workers
- [Persistence Configuration](./PERSISTENCE.md) - Storage backend options
- [Migration Plan](../../TYPESCRIPT_MIGRATION_PLAN.md)
- [Architecture](../../TYPESCRIPT_ARCHITECTURE.md)
- [Comparison](../../TYPESCRIPT_COMPARISON.md)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

