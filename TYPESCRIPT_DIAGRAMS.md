# Architecture Diagrams

Visual representations of the TypeScript migration architecture.

## System Architecture

### Current Dart/Flutter Architecture

```
┌─────────────────────────────────────────────┐
│         Flutter Application                 │
│  (iOS, Android, Web, Desktop)               │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│    declarative_sqlite_flutter               │
│  • DatabaseProvider (InheritedWidget)       │
│  • QueryListView (Reactive Widget)          │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│        declarative_sqlite (CORE)            │
│  • Schema Definition & Migration            │
│  • CRUD & Query Builders                    │
│  • Custom Streaming Queries                 │
│  • HLC-based Sync                           │
│  • File Management                          │
│  • DbRecord Base Class                      │
└─────────────────────────────────────────────┘
                    ↑
┌─────────────────────────────────────────────┐
│    declarative_sqlite_generator             │
│  • @GenerateDbRecord annotation             │
│  • Typed accessor generation                │
│  • Factory registration                     │
│  • REQUIRED (no reflection in Dart)         │
└─────────────────────────────────────────────┘
         ↓ (build_runner)
┌─────────────────────────────────────────────┐
│         Generated Code (.db.dart)           │
│  • user.db.dart                             │
│  • post.db.dart                             │
│  • sqlite_factory_registration.dart         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│            sqflite (Native)                 │
│  • Flutter SQLite wrapper                   │
│  • Platform channels to native code         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│         Native SQLite (C Library)           │
│  • iOS: Built-in SQLite                     │
│  • Android: Built-in SQLite                 │
└─────────────────────────────────────────────┘
```

### Future TypeScript/PWA/Capacitor Architecture

```
┌─────────────────────────────────────────────┐
│   PWA / Capacitor Application               │
│  (Browser, iOS, Android)                    │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│    UI Framework (React, Vue, Svelte, etc)   │
│  • Components consume RxJS Observables      │
│  • No special widgets needed                │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  @declarative-sqlite/core (CORE)            │
│  • Schema Definition & Migration            │
│  • CRUD & Query Builders                    │
│  • RxJS Streaming Queries ⭐                │
│  • HLC-based Sync                           │
│  • File Management                          │
│  • Proxy-based DbRecord ⭐                  │
│  • NO CODE GENERATION REQUIRED ⭐           │
└─────────────────────────────────────────────┘
         ↓                           ↓
┌────────────────────┐    ┌────────────────────┐
│  Optional:         │    │  SQLite Adapter    │
│  @declarative-     │    │  (Pluggable)       │
│   sqlite/generator │    │                    │
│  • Decorators      │    └────────────────────┘
│  • Type extraction │         ↓          ↓
│  • Dev-only        │    ┌─────┐    ┌────────┐
└────────────────────┘    │PWA  │    │Mobile  │
                          └─────┘    └────────┘
                             ↓           ↓
                    ┌──────────────┐ ┌────────────────┐
                    │  wa-sqlite   │ │ Capacitor      │
                    │  (WASM)      │ │ SQLite Plugin  │
                    └──────────────┘ └────────────────┘
                             ↓           ↓
                    ┌──────────────┐ ┌────────────────┐
                    │ SQLite WASM  │ │ Native SQLite  │
                    │ (Browser)    │ │ (iOS/Android)  │
                    └──────────────┘ └────────────────┘
```

## Code Generation Comparison

### Dart: Required Code Generation

```
┌─────────────────────────────────────────────┐
│  1. Write Schema & DbRecord Class           │
│                                             │
│  @GenerateDbRecord('users')                 │
│  class User extends DbRecord { }            │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  2. Run build_runner                        │
│                                             │
│  $ dart run build_runner build              │
│  [INFO] Running build...                    │
│  [INFO] Generating code...                  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  3. Generated Code Created                  │
│                                             │
│  user.db.dart:                              │
│    extension UserExtension on User {        │
│      String get name => getValue('name');   │
│      set name(String v) => setValue(...);   │
│    }                                        │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  4. Use Generated Code                      │
│                                             │
│  final user = User({}, database);           │
│  user.name = 'Alice';  // Uses extension    │
└─────────────────────────────────────────────┘

Time per change: ~5-30 seconds (build_runner)
```

### TypeScript: Zero Code Generation

```
┌─────────────────────────────────────────────┐
│  1. Define TypeScript Interface             │
│                                             │
│  interface User {                           │
│    name: string;                            │
│    age: number;                             │
│  }                                          │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  2. Use Immediately (No Build!)             │
│                                             │
│  const user = db.createRecord<User>('users');│
│  user.name = 'Alice';  // Type-safe!        │
│  console.log(user.age); // Type-checked!    │
└─────────────────────────────────────────────┘

Time per change: ~0 seconds (instant)
```

## Data Flow Comparison

### Dart: Insert Operation

```
App Code
   ↓
await db.insert('users', data)
   ↓
DeclarativeDatabase.insert()
   ↓
Generate system columns
(system_id, system_created_at, system_version)
   ↓
Add to dirty row store
   ↓
Execute SQL via sqflite
   ↓
Platform channel to native
   ↓
Native SQLite INSERT
   ↓
Notify stream listeners
   ↓
Custom Stream emits update
   ↓
UI rebuilds (StreamBuilder)
```

### TypeScript: Insert Operation

```
App Code
   ↓
await db.insert('users', data)
   ↓
DeclarativeDatabase.insert()
   ↓
Generate system columns
(system_id, system_created_at, system_version)
   ↓
Add to dirty row store + emit event
   ↓
Execute SQL via adapter
   ↓
wa-sqlite (WASM) or Capacitor SQLite
   ↓
SQLite INSERT
   ↓
Notify stream listeners
   ↓
RxJS Observable emits update
   ↓
UI updates (subscribe callback)
```

## Migration System Flow

### Schema Migration Process (Same for Both)

```
┌─────────────────────────────────────────────┐
│  1. Declarative Schema Definition           │
│                                             │
│  const schema = SchemaBuilder()             │
│    .table('users', t => {                   │
│      t.text('name');                        │
│      t.integer('age');                      │
│    })                                       │
│    .build();                                │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  2. Introspect Live Database                │
│                                             │
│  • PRAGMA table_info(users)                 │
│  • PRAGMA index_list(users)                 │
│  • PRAGMA foreign_key_list(users)           │
│  → Build LiveSchema object                  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  3. Compare Schemas (Diff)                  │
│                                             │
│  SchemaDiff:                                │
│  • Tables to create: ['posts']              │
│  • Columns to add: ['email' in 'users']     │
│  • Columns to drop: []                      │
│  • Keys to modify: ['unique_email']         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  4. Generate Migration Scripts              │
│                                             │
│  ALTER TABLE users ADD COLUMN email TEXT;   │
│  CREATE UNIQUE INDEX idx_email ON users...  │
│  -- or table recreation if needed --        │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  5. Execute in Transaction                  │
│                                             │
│  BEGIN TRANSACTION;                         │
│    -- migration SQL --                      │
│  COMMIT;                                    │
│  (or ROLLBACK on error)                     │
└─────────────────────────────────────────────┘
```

## Streaming Query Architecture

### Dart: Custom Stream Implementation

```
Query Definition
   ↓
StreamingQuery.create()
   ↓
Execute initial query
   ↓
Store result in cache
   ↓
Listen for database changes
(custom change notification)
   ↓
On change: re-execute query
   ↓
Compare with cached result
   ↓
If different: emit to Stream
   ↓
StreamBuilder rebuilds widget
```

### TypeScript: RxJS Observable

```
Query Definition
   ↓
db.stream(q => q.from('users'))
   ↓
Create RxJS Observable
   ↓
Execute initial query
   ↓
Emit initial result
   ↓
Listen for 'dataChanged' events
   ↓
On change: re-execute query
   ↓
pipe(distinctUntilChanged())
   ↓
Apply RxJS operators:
  • map, filter, debounce, etc.
   ↓
subscribe() callback
   ↓
Update UI
```

## Package Dependencies

### Dart Package Dependency Tree

```
my_app
 ├── declarative_sqlite: ^1.4.0
 │    ├── sqflite_common: ^2.5.6
 │    ├── path_provider: ^2.1.5
 │    ├── uuid: ^4.5.1
 │    ├── rxdart: ^0.28.0
 │    └── (8 more dependencies)
 │
 ├── declarative_sqlite_flutter: ^1.4.0
 │    └── declarative_sqlite: ^1.4.0
 │
 └── dev:
      └── declarative_sqlite_generator: ^1.4.0
           ├── build: ^4.0.0
           ├── source_gen: ^4.0.1
           ├── analyzer: ^8.2.0
           └── (6 more dependencies)

Total dev dependencies: ~15+
Total runtime dependencies: ~10+
```

### TypeScript Package Dependency Tree

```
my_app
 └── @declarative-sqlite/core: ^1.0.0
      ├── rxjs: ^7.8.0          (peer dependency)
      └── wa-sqlite: ^0.9.0     (or @capacitor-community/sqlite)

Optional dev:
 └── @declarative-sqlite/generator: ^1.0.0
      └── reflect-metadata: ^0.1.0

Total runtime dependencies: ~2-3
Total dev dependencies: 0-1 (optional)
```

## Bundle Size Breakdown

### Dart/Flutter (Compiled App Size)

```
iOS App:
┌──────────────────────────────────┐
│ Flutter Engine        │ ~15 MB   │
│ App Code (compiled)   │  ~5 MB   │
│ declarative_sqlite    │  ~0.5MB  │
│ Other dependencies    │  ~2 MB   │
│ Assets                │  ~1 MB   │
├──────────────────────────────────┤
│ TOTAL                 │ ~23 MB   │
└──────────────────────────────────┘
```

### TypeScript/PWA (Initial Load)

```
First Load:
┌──────────────────────────────────┐
│ HTML                  │  ~2 KB   │
│ CSS                   │  ~10 KB  │
│ App Code (bundled)    │  ~100 KB │
│ @declarative-sqlite   │  ~45 KB  │
│ RxJS                  │  ~20 KB  │
│ wa-sqlite WASM        │  ~400 KB │
├──────────────────────────────────┤
│ TOTAL                 │ ~577 KB  │
└──────────────────────────────────┘

All sizes gzipped, WASM cached by browser
```

## Development Workflow

### Dart Development Loop

```
1. Edit Code
   ↓
2. Save File
   ↓ (if schema/record changes)
3. Run build_runner build
   ↓ (~5-30 seconds)
4. Generated code created
   ↓
5. Hot reload (if Flutter)
   ↓
6. Test in emulator/device
   ↓
7. Repeat

Schema change cycle: ~30-60 seconds
```

### TypeScript Development Loop

```
1. Edit Code
   ↓
2. Save File
   ↓ (Vite HMR)
3. Browser updates instantly
   ↓ (<100ms)
4. Test in browser
   ↓
5. Repeat

Schema change cycle: <1 second
```

## Deployment Comparison

### Dart/Flutter Deployment

```
Development → Production:

1. Build release version
   └─ flutter build ios/android/web
      (~5-10 minutes)
   
2. Sign app
   └─ iOS: Xcode signing
   └─ Android: Key signing
   
3. Upload to stores
   └─ iOS: App Store Connect
   └─ Android: Play Console
   
4. Wait for review
   └─ iOS: 1-7 days
   └─ Android: hours-days
   
5. Users update
   └─ Manual app update
   └─ Weeks for full adoption

Time to production: 1-7+ days
Time to users: 1-4+ weeks
```

### TypeScript/PWA Deployment

```
Development → Production:

1. Build production bundle
   └─ npm run build
      (~10-30 seconds)
   
2. Deploy to CDN
   └─ Vercel/Netlify/Cloudflare
      (~30 seconds)
   
3. Live immediately
   └─ Service Worker updates
   
4. Users get update
   └─ Automatic on next visit
   └─ Hours for full adoption

Time to production: <2 minutes
Time to users: hours
```

## Summary

The TypeScript migration provides:

1. ✅ **Simpler Development** - No code generation build step
2. ✅ **Faster Iteration** - Instant feedback with Vite HMR
3. ✅ **Smaller Bundles** - 90% reduction in library size
4. ✅ **Easier Deployment** - PWA instant updates vs app store
5. ✅ **Better DX** - Industry-standard tools (RxJS, TypeScript, Vitest)
6. ✅ **Wider Reach** - Browser + mobile via Capacitor

While maintaining:
- ✅ All core features (schema, migration, CRUD, sync, files, streaming)
- ✅ Type safety (TypeScript types + runtime Proxy)
- ✅ Performance (WASM SQLite ~80% of native)
- ✅ Offline support (Service Workers, IndexedDB)

---

**Diagrams Version**: 1.0  
**Last Updated**: 2024-12-06
