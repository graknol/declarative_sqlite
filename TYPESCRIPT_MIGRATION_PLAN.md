# TypeScript Migration Plan for declarative_sqlite

## Executive Summary

This document outlines a comprehensive plan to migrate the declarative_sqlite library from Dart to TypeScript for use in PWA and Capacitor applications. The migration will maintain core functionality while leveraging TypeScript's capabilities to reduce complexity and improve developer experience.

## Current State Analysis

### Dart Codebase Overview

**Core Library (`declarative_sqlite`)**: ~6,500 lines of code across 56 files
- **Schema System**: Fluent builders for declarative database schema definition
- **Auto-Migration**: Automatic schema diffing and migration script generation
- **CRUD Operations**: Type-safe database operations with streaming support
- **Sync System**: HLC-based conflict resolution and dirty row tracking
- **File Management**: Integrated file storage with versioning
- **Streaming Queries**: Reactive queries with automatic dependency tracking

**Generator Library (`declarative_sqlite_generator`)**: Build-time code generation
- Generates typed accessors for DbRecord classes
- Creates factory registration code
- Required due to Dart's lack of runtime reflection

**Flutter Integration (`declarative_sqlite_flutter`)**: Flutter-specific widgets
- DatabaseProvider (InheritedWidget)
- QueryListView (reactive ListView)

### Key Components to Migrate

#### 1. Schema Definition (Critical)
- `SchemaBuilder`: Entry point for schema definition
- `TableBuilder`, `ViewBuilder`: Table and view definitions
- Column builders: `TextColumnBuilder`, `IntegerColumnBuilder`, etc.
- `KeyBuilder`: Primary keys and indices
- System tables: `__settings`, `__files`, `__dirty_rows`

**Complexity**: High - Foundation of entire system
**LOC**: ~800 lines
**Priority**: 1

#### 2. Migration System (Critical)
- `introspect_schema.dart`: Read live database schema via PRAGMA
- `diff_schemas.dart`: Compare declarative vs live schemas
- `generate_migration_scripts.dart`: Generate ALTER TABLE scripts
- `schema_diff.dart`: Data structures for schema differences

**Complexity**: High - Complex SQL generation logic
**LOC**: ~600 lines
**Priority**: 1

#### 3. Database Operations (Critical)
- `DeclarativeDatabase`: Main database interface (~1,324 lines)
  - CRUD operations (insert, update, delete, query)
  - Raw SQL execution
  - Bulk operations with constraint handling
  - Database lifecycle (open, close, initialize)
- `QueryBuilder`: Fluent query construction (~239 lines)
- `WhereClause`: SQL WHERE clause building (~236 lines)

**Complexity**: Medium-High
**LOC**: ~1,800 lines
**Priority**: 2

#### 4. Synchronization (Important)
- `hlc.dart`: Hybrid Logical Clock implementation (~146 lines)
- `dirty_row_store.dart`: Change tracking interface (~60 lines)
- `sqlite_dirty_row_store.dart`: SQLite-based implementation (~89 lines)
- `dirty_row.dart`: DirtyRow data structure (~50 lines)

**Complexity**: Medium - Algorithm implementation
**LOC**: ~345 lines
**Priority**: 3

#### 5. File Management (Important)
- `file_repository.dart`: File storage interface (~45 lines)
- `filesystem_file_repository.dart`: Filesystem implementation (~124 lines)
- `fileset.dart`: File operations API (~201 lines)
- `fileset_field.dart`: Fileset field tracking (~123 lines)

**Complexity**: Medium
**LOC**: ~493 lines
**Priority**: 4

#### 6. Streaming Queries (Important)
- `streaming_query.dart`: Reactive query implementation (~525 lines)
- `query_stream_manager.dart`: Stream lifecycle management (~449 lines)
- `query_dependency_analyzer.dart`: Automatic dependency tracking (~200 lines)

**Complexity**: Medium-High - Complex state management
**LOC**: ~1,174 lines
**Priority**: 5

#### 7. DbRecord & Type Safety (Important)
- `db_record.dart`: Base class for typed records (~500 lines)
- `record_factory.dart`: Factory pattern for records (~50 lines)
- `record_map_factory_registry.dart`: Factory registration (~60 lines)

**Complexity**: Medium
**LOC**: ~610 lines
**Priority**: 6

#### 8. Error Handling (Moderate)
- `db_exceptions.dart`: Custom exception types (~396 lines)
- `db_exception_mapper.dart`: SQLite error mapping (~435 lines)
- `db_exception_wrapper.dart`: Exception wrapping (~374 lines)

**Complexity**: Low-Medium
**LOC**: ~1,205 lines
**Priority**: 7

#### 9. Task Scheduling (Nice-to-Have)
- `task_scheduler.dart`: Database maintenance scheduling (~551 lines)
- `database_maintenance_tasks.dart`: Cleanup tasks (~120 lines)

**Complexity**: Low-Medium
**LOC**: ~671 lines
**Priority**: 8

#### 10. Utilities (Easy)
- `value_serializer.dart`: Type conversion (~19 lines)
- `sql_escaping_utils.dart`: SQL escaping (~3 lines)
- `string_utils.dart`: String utilities (~8 lines)

**Complexity**: Low
**LOC**: ~30 lines
**Priority**: 9

### Not Migrating (Flutter-Specific)
- `declarative_sqlite_flutter` package
- `DatabaseProvider`, `QueryListView` widgets
- Flutter-specific dependencies

**Reason**: PWA/Capacitor uses standard web components, not Flutter widgets

## TypeScript Architecture

### Technology Stack

#### SQLite Implementation Options

1. **wa-sqlite** (Recommended Primary)
   - WebAssembly-based SQLite
   - Works in browser and Node.js
   - Good performance
   - Official SQLite WASM builds available
   - Best for PWA

2. **@capacitor-community/sqlite** (Recommended Mobile)
   - Native SQLite for iOS/Android via Capacitor
   - Better performance on mobile
   - Capacitor plugin integration
   - Fallback for mobile platforms

3. **better-sqlite3** (Node.js Development/Testing)
   - Synchronous API
   - Fastest for Node.js
   - Great for testing
   - Not usable in browser

**Strategy**: Abstract SQLite interface, support multiple backends via adapter pattern

#### Build & Development Tools

- **TypeScript 5.x**: Latest features, strict mode
- **Vite**: Fast build tool, HMR, optimized bundling
- **Vitest**: Fast testing framework, compatible with Vite
- **ESLint + Prettier**: Code quality and formatting
- **pnpm**: Fast, efficient package manager
- **tsup**: TypeScript library bundler
- **typedoc**: API documentation generation

#### Runtime Dependencies

**Keep Minimal**:
- `rxjs`: Reactive streams for streaming queries
- SQLite adapter (wa-sqlite or capacitor-sqlite)
- `uuid`: GUID generation (or use built-in crypto.randomUUID)

**No Dependencies for**:
- Schema building (pure TypeScript)
- Migration (pure SQL generation)
- HLC implementation (pure logic)

### Project Structure

```
declarative-sqlite-ts/
├── packages/
│   ├── core/                           # @declarative-sqlite/core
│   │   ├── src/
│   │   │   ├── index.ts                # Main entry point
│   │   │   │
│   │   │   ├── adapters/               # SQLite adapter layer
│   │   │   │   ├── adapter.interface.ts
│   │   │   │   ├── wa-sqlite.adapter.ts
│   │   │   │   ├── capacitor.adapter.ts
│   │   │   │   └── better-sqlite3.adapter.ts (dev only)
│   │   │   │
│   │   │   ├── schema/                 # Schema definition
│   │   │   │   ├── builders/
│   │   │   │   │   ├── schema-builder.ts
│   │   │   │   │   ├── table-builder.ts
│   │   │   │   │   ├── view-builder.ts
│   │   │   │   │   ├── column-builders/
│   │   │   │   │   │   ├── base-column-builder.ts
│   │   │   │   │   │   ├── text-column-builder.ts
│   │   │   │   │   │   ├── integer-column-builder.ts
│   │   │   │   │   │   ├── real-column-builder.ts
│   │   │   │   │   │   ├── guid-column-builder.ts
│   │   │   │   │   │   ├── date-column-builder.ts
│   │   │   │   │   │   └── fileset-column-builder.ts
│   │   │   │   │   └── key-builder.ts
│   │   │   │   ├── types/
│   │   │   │   │   ├── schema.ts
│   │   │   │   │   ├── table.ts
│   │   │   │   │   ├── view.ts
│   │   │   │   │   ├── column.ts
│   │   │   │   │   └── key.ts
│   │   │   │   └── system-tables.ts
│   │   │   │
│   │   │   ├── migration/              # Auto-migration system
│   │   │   │   ├── introspector.ts     # Read live schema
│   │   │   │   ├── differ.ts           # Compare schemas
│   │   │   │   ├── generator.ts        # Generate SQL scripts
│   │   │   │   ├── migrator.ts         # Execute migrations
│   │   │   │   └── types.ts            # Migration types
│   │   │   │
│   │   │   ├── database/               # Database operations
│   │   │   │   ├── declarative-database.ts  # Main class
│   │   │   │   ├── crud-operations.ts       # CRUD methods
│   │   │   │   ├── bulk-operations.ts       # Bulk load
│   │   │   │   ├── raw-sql.ts               # Raw SQL
│   │   │   │   └── initialization.ts        # DB setup
│   │   │   │
│   │   │   ├── query/                  # Query builders
│   │   │   │   ├── query-builder.ts
│   │   │   │   ├── where-clause.ts
│   │   │   │   ├── join-clause.ts
│   │   │   │   ├── query-column.ts
│   │   │   │   └── types.ts
│   │   │   │
│   │   │   ├── sync/                   # Synchronization
│   │   │   │   ├── hlc/
│   │   │   │   │   ├── hlc-clock.ts
│   │   │   │   │   ├── hlc-timestamp.ts
│   │   │   │   │   └── node-id.ts
│   │   │   │   ├── dirty-rows/
│   │   │   │   │   ├── dirty-row.ts
│   │   │   │   │   ├── dirty-row-store.interface.ts
│   │   │   │   │   └── sqlite-dirty-row-store.ts
│   │   │   │   └── lww/
│   │   │   │       ├── lww-manager.ts
│   │   │   │       └── lww-column.ts
│   │   │   │
│   │   │   ├── files/                  # File management
│   │   │   │   ├── file-repository.interface.ts
│   │   │   │   ├── filesystem-repository.ts
│   │   │   │   ├── fileset.ts
│   │   │   │   ├── fileset-field.ts
│   │   │   │   └── types.ts
│   │   │   │
│   │   │   ├── streaming/              # Streaming queries
│   │   │   │   ├── streaming-query.ts
│   │   │   │   ├── query-stream-manager.ts
│   │   │   │   ├── dependency-analyzer.ts
│   │   │   │   └── types.ts
│   │   │   │
│   │   │   ├── records/                # DbRecord system
│   │   │   │   ├── db-record.ts
│   │   │   │   ├── record-factory.ts
│   │   │   │   ├── record-registry.ts
│   │   │   │   └── typed-record.ts     # TypeScript-specific
│   │   │   │
│   │   │   ├── exceptions/             # Error handling
│   │   │   │   ├── database-exceptions.ts
│   │   │   │   ├── exception-mapper.ts
│   │   │   │   └── exception-wrapper.ts
│   │   │   │
│   │   │   ├── scheduling/             # Task scheduling
│   │   │   │   ├── task-scheduler.ts
│   │   │   │   └── maintenance-tasks.ts
│   │   │   │
│   │   │   └── utils/                  # Utilities
│   │   │       ├── sql-escaping.ts
│   │   │       ├── value-serializer.ts
│   │   │       ├── type-guards.ts
│   │   │       └── constants.ts
│   │   │
│   │   ├── tests/                      # Unit & integration tests
│   │   │   ├── schema/
│   │   │   ├── migration/
│   │   │   ├── database/
│   │   │   ├── query/
│   │   │   ├── sync/
│   │   │   ├── files/
│   │   │   ├── streaming/
│   │   │   └── helpers/
│   │   │
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── tsconfig.build.json
│   │   ├── vite.config.ts
│   │   └── README.md
│   │
│   └── generator/                      # @declarative-sqlite/generator (optional)
│       ├── src/
│       │   ├── index.ts
│       │   ├── decorator.ts            # @Table, @Column decorators
│       │   ├── schema-extractor.ts     # Extract schema from decorators
│       │   ├── type-generator.ts       # Generate types
│       │   └── cli.ts                  # CLI tool
│       ├── tests/
│       ├── package.json
│       └── README.md
│
├── examples/
│   ├── 01-basic-crud/
│   │   ├── src/
│   │   │   ├── index.ts
│   │   │   └── schema.ts
│   │   └── package.json
│   │
│   ├── 02-streaming-queries/
│   │   ├── src/
│   │   └── package.json
│   │
│   ├── 03-offline-sync/
│   │   ├── src/
│   │   └── package.json
│   │
│   ├── 04-pwa-app/
│   │   ├── src/
│   │   ├── public/
│   │   ├── index.html
│   │   └── package.json
│   │
│   └── 05-capacitor-app/
│       ├── src/
│       ├── capacitor.config.ts
│       └── package.json
│
├── docs/
│   ├── api/                            # Generated API docs
│   ├── guides/
│   │   ├── getting-started.md
│   │   ├── schema-definition.md
│   │   ├── migrations.md
│   │   ├── streaming-queries.md
│   │   ├── offline-sync.md
│   │   ├── file-management.md
│   │   └── migration-from-dart.md
│   └── README.md
│
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── publish.yml
│
├── package.json                        # Workspace root
├── pnpm-workspace.yaml
├── tsconfig.base.json
├── .eslintrc.json
├── .prettierrc
├── .gitignore
└── README.md
```

### TypeScript-Specific Improvements

#### 1. Eliminate Code Generation (Potentially)

**Dart Problem**: No reflection → needs code generation for typed accessors

**TypeScript Solution**: Multiple approaches available

**Option A: Proxy-Based (Zero Build Step)**
```typescript
import { DbRecord } from '@declarative-sqlite/core';

// Define schema
const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id');
    t.text('name');
    t.integer('age');
    t.text('email');
  })
  .build();

// Use with Proxy for typed access
interface UserData {
  id: string;
  name: string;
  age: number;
  email: string;
}

const user = db.createRecord<UserData>('users', {});
user.name = 'Alice';  // Type-safe, no codegen!
user.age = 30;
console.log(user.email);  // Type-checked
```

**Implementation**:
```typescript
class DbRecord<T extends Record<string, any>> {
  private data: Map<string, any>;
  
  constructor(tableName: string, initialData: Partial<T>) {
    this.data = new Map(Object.entries(initialData));
    
    // Return Proxy for typed access
    return new Proxy(this, {
      get(target, prop: string) {
        if (prop in target) return target[prop];
        return target.getValue(prop);
      },
      set(target, prop: string, value) {
        if (prop in target) {
          target[prop] = value;
        } else {
          target.setValue(prop, value);
        }
        return true;
      }
    }) as DbRecord<T> & T;
  }
}
```

**Option B: Decorator-Based (Optional Build Step)**
```typescript
import { Table, Column, PrimaryKey } from '@declarative-sqlite/generator';

@Table('users')
class User extends DbRecord {
  @PrimaryKey()
  @Column('guid')
  id!: string;
  
  @Column('text')
  name!: string;
  
  @Column('integer')
  age!: number;
  
  @Column('text')
  email!: string;
}

// Generate schema from decorators
const schema = SchemaExtractor.extractSchema(User);
```

**Recommendation**: 
- **Core library**: Use Proxy-based approach (no build step required)
- **Generator package**: Optional decorator-based approach for those who prefer it
- Keep generator as dev dependency only, not required for runtime

#### 2. Better Type Inference

**Dart**: Limited type inference, explicit types often needed

**TypeScript**: Strong inference, generics, mapped types

```typescript
// Query builder with type inference
const users = await db.query(q => 
  q.from('users')
   .select('name', 'age')  // Inferred: { name: string, age: number }[]
   .where('age', '>', 18)
);

// Streaming with RxJS
const users$ = db.stream(q => q.from('users'))
  .pipe(
    map(users => users.filter(u => u.age > 18)),
    debounceTime(300)
  );

users$.subscribe(users => console.log(users));
```

#### 3. Simplified Error Handling

**Dart**: Custom exception hierarchy, try-catch

**TypeScript**: Union types, Result type pattern

```typescript
// Option 1: Traditional exceptions (like Dart)
try {
  await db.insert('users', userData);
} catch (e) {
  if (e instanceof ConstraintViolationError) {
    console.error('Constraint violated:', e.constraint);
  }
}

// Option 2: Result type (more functional)
type Result<T, E = Error> = 
  | { ok: true; value: T }
  | { ok: false; error: E };

const result = await db.insertSafe('users', userData);
if (result.ok) {
  console.log('Inserted:', result.value);
} else {
  console.error('Error:', result.error);
}

// Option 3: Promise rejection (simplest)
db.insert('users', userData)
  .then(id => console.log('Inserted:', id))
  .catch(err => console.error('Error:', err));
```

**Recommendation**: Support all three patterns, default to traditional exceptions for API consistency

#### 4. Native Async Patterns

**Dart**: Future and Stream are separate concepts

**TypeScript**: Promises, async/await, async iterables

```typescript
// Async iteration
for await (const user of db.queryIterable('users')) {
  console.log(user.name);
}

// Promise.all for parallel operations
const [users, posts] = await Promise.all([
  db.query(q => q.from('users')),
  db.query(q => q.from('posts'))
]);

// Streaming with RxJS Observable
const users$ = db.stream(q => q.from('users'));
```

#### 5. SQLite Adapter Abstraction

Abstract SQLite operations to support multiple backends:

```typescript
interface SQLiteAdapter {
  open(path: string): Promise<void>;
  close(): Promise<void>;
  exec(sql: string): Promise<void>;
  prepare(sql: string): PreparedStatement;
  transaction<T>(callback: () => Promise<T>): Promise<T>;
}

interface PreparedStatement {
  run(...params: any[]): Promise<{ changes: number; lastInsertRowid: number }>;
  get(...params: any[]): Promise<any>;
  all(...params: any[]): Promise<any[]>;
  finalize(): Promise<void>;
}

// Implementations
class WaSqliteAdapter implements SQLiteAdapter { /* ... */ }
class CapacitorSqliteAdapter implements SQLiteAdapter { /* ... */ }
class BetterSqlite3Adapter implements SQLiteAdapter { /* ... */ }

// Usage
const db = new DeclarativeDatabase({
  schema,
  adapter: new WaSqliteAdapter(),  // Or CapacitorSqliteAdapter
  // ... other options
});
```

## Complexity Reduction Strategies

### 1. Eliminate Dart-Specific Patterns

#### Remove: Equatable Package
**Dart**: Uses `Equatable` for value equality
```dart
class Schema extends Equatable {
  final List<DbTable> tables;
  
  @override
  List<Object?> get props => [tables];
}
```

**TypeScript**: Use plain equality or JSON comparison
```typescript
class Schema {
  constructor(
    public readonly tables: DbTable[]
  ) {}
  
  equals(other: Schema): boolean {
    return JSON.stringify(this) === JSON.stringify(other);
  }
}
```

#### Remove: Meta Package Annotations
**Dart**: Uses `@immutable`, `@protected` annotations

**TypeScript**: Use language features
```typescript
// Immutable via readonly
class Schema {
  constructor(
    public readonly tables: readonly DbTable[]
  ) {}
}

// Protected via TypeScript visibility
class DbRecord {
  protected getValue(key: string): any {
    // ...
  }
}
```

### 2. Simplify Builder Patterns

**Dart**: Verbose builder pattern
```dart
final builder = SchemaBuilder();
builder.table('users', (table) {
  table.text('name').notNull('Default');
  table.integer('age').notNull(0);
  table.key(['id']).primary();
});
final schema = builder.build();
```

**TypeScript**: More concise, still fluent
```typescript
const schema = new SchemaBuilder()
  .table('users', t => {
    t.text('name').notNull('Default');
    t.integer('age').notNull(0);
    t.key('id').primary();
  })
  .build();

// Or even more concise with object syntax
const schema = defineSchema({
  users: {
    name: { type: 'text', notNull: true, default: 'Default' },
    age: { type: 'integer', notNull: true, default: 0 },
    _keys: { id: 'primary' }
  }
});
```

**Recommendation**: Support both fluent and object syntax

### 3. Leverage TypeScript's Type System

#### Typed Query Results
```typescript
// Define table type
type UsersTable = {
  id: string;
  name: string;
  age: number;
  email: string;
};

// Query with type inference
const users = await db.query<UsersTable>(q => 
  q.from('users')
   .select('name', 'age')  // Type: Pick<UsersTable, 'name' | 'age'>[]
);

// users is typed as: { name: string; age: number }[]
```

#### Typed Schema Definition
```typescript
// Define schema with full type safety
const schema = new SchemaBuilder()
  .table<UsersTable>('users', t => {
    t.guid('id');      // Type-checked against UsersTable
    t.text('name');    // Autocomplete!
    t.integer('age');
    t.text('email');
  })
  .build();
```

### 4. Simplify Streaming Queries

**Dart**: Custom Stream implementation

**TypeScript**: Use RxJS (industry standard)
```typescript
import { Observable } from 'rxjs';
import { map, filter, debounceTime } from 'rxjs/operators';

// Streaming query returns Observable
const users$: Observable<User[]> = db.stream(q => q.from('users'));

// Use RxJS operators
users$
  .pipe(
    map(users => users.filter(u => u.age > 18)),
    debounceTime(300),
    filter(users => users.length > 0)
  )
  .subscribe(users => {
    console.log('Adult users:', users);
  });
```

### 5. Remove Unnecessary Abstractions

#### Consolidate Exception Types
**Dart**: Many specific exception classes (23+ classes)

**TypeScript**: Fewer, more general exceptions with metadata
```typescript
class DatabaseError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly details?: Record<string, any>
  ) {
    super(message);
    this.name = 'DatabaseError';
  }
}

// Usage
throw new DatabaseError(
  'Constraint violation',
  'CONSTRAINT_VIOLATION',
  { constraint: 'unique_email', table: 'users' }
);

// Type guards for specific errors
function isConstraintError(err: unknown): err is DatabaseError {
  return err instanceof DatabaseError && 
         err.code === 'CONSTRAINT_VIOLATION';
}
```

## Migration Phases in Detail

### Phase 1: Foundation Setup (Week 1)

**Goals**: 
- Project structure
- Build tooling
- Testing framework
- SQLite adapter layer

**Deliverables**:
1. Monorepo with pnpm workspaces
2. TypeScript configuration (strict mode)
3. Vite + Vitest setup
4. ESLint + Prettier configuration
5. SQLite adapter interface + wa-sqlite implementation
6. Basic CI/CD pipeline

**Tasks**:
- [ ] Initialize pnpm workspace
- [ ] Create core package structure
- [ ] Configure TypeScript with strict mode
- [ ] Set up Vitest for testing
- [ ] Implement SQLiteAdapter interface
- [ ] Create WaSqliteAdapter implementation
- [ ] Write adapter tests
- [ ] Set up GitHub Actions CI

### Phase 2: Schema System (Week 2-3)

**Goals**: Port schema definition and system tables

**Deliverables**:
1. SchemaBuilder with fluent API
2. TableBuilder and column builders
3. ViewBuilder for SQL views
4. KeyBuilder for indices
5. Schema data structures
6. System tables implementation

**Tasks**:
- [ ] Port Schema, DbTable, DbView, DbColumn, DbKey classes
- [ ] Implement SchemaBuilder
- [ ] Implement TableBuilder
- [ ] Port all column builders (Text, Integer, Real, GUID, Date, Fileset)
- [ ] Implement ViewBuilder
- [ ] Implement KeyBuilder
- [ ] Add system tables (__settings, __files, __dirty_rows)
- [ ] Write comprehensive schema tests
- [ ] Add schema validation

### Phase 3: Migration Engine (Week 4-5)

**Goals**: Automatic schema migration system

**Deliverables**:
1. Schema introspection from live database
2. Schema diff algorithm
3. Migration script generation
4. Migration execution with transactions

**Tasks**:
- [ ] Port schema introspection (PRAGMA queries)
- [ ] Implement schema differ
- [ ] Port migration script generation
- [ ] Add table recreation for complex changes
- [ ] Implement migration executor
- [ ] Handle data preservation during migrations
- [ ] Write migration integration tests
- [ ] Test edge cases (add/drop columns, constraints, etc.)

### Phase 4: Database Operations (Week 6-7)

**Goals**: Core CRUD operations and query building

**Deliverables**:
1. DeclarativeDatabase main class
2. CRUD operations (insert, update, delete, query)
3. Raw SQL execution
4. Bulk operations with constraint handling
5. QueryBuilder with fluent API
6. WhereClause and JoinClause

**Tasks**:
- [ ] Port DeclarativeDatabase class
- [ ] Implement insert/update/delete operations
- [ ] Add query methods with type safety
- [ ] Port QueryBuilder
- [ ] Implement WhereClause
- [ ] Add bulk load with constraint violation strategies
- [ ] Implement raw SQL methods
- [ ] Add transaction support (simplified)
- [ ] Write CRUD operation tests
- [ ] Write query builder tests

### Phase 5: Synchronization System (Week 8-9)

**Goals**: HLC, LWW, and dirty row tracking

**Deliverables**:
1. Hybrid Logical Clock implementation
2. Last-Write-Wins conflict resolution
3. Dirty row tracking
4. Change event streaming

**Tasks**:
- [ ] Port HLC clock and timestamp classes
- [ ] Implement node ID management
- [ ] Port LWW column management
- [ ] Automatic __hlc column generation
- [ ] Port DirtyRow and DirtyRowStore
- [ ] Implement SqliteDirtyRowStore
- [ ] Add dirty row event streaming
- [ ] Write HLC tests
- [ ] Write LWW tests
- [ ] Write dirty row tracking tests

### Phase 6: File Management (Week 10)

**Goals**: File storage and versioning

**Deliverables**:
1. File repository interface
2. Filesystem implementation
3. FileSet API
4. Fileset column support

**Tasks**:
- [ ] Port IFileRepository interface
- [ ] Implement FilesystemFileRepository
- [ ] Port FileSet API
- [ ] Add fileset field tracking
- [ ] Integrate with __files table
- [ ] Write file management tests
- [ ] Test file versioning

### Phase 7: Streaming Queries (Week 11-12)

**Goals**: Reactive queries with RxJS

**Deliverables**:
1. StreamingQuery with RxJS Observable
2. Query dependency analysis
3. Automatic re-execution on changes
4. QueryStreamManager for lifecycle

**Tasks**:
- [ ] Port streaming query logic to RxJS
- [ ] Implement query dependency analyzer
- [ ] Add automatic re-execution on data changes
- [ ] Port QueryStreamManager
- [ ] Optimize query execution
- [ ] Write streaming query tests
- [ ] Performance benchmarks

### Phase 8: DbRecord System (Week 13)

**Goals**: Type-safe record access

**Deliverables**:
1. DbRecord base class
2. Proxy-based typed access
3. Factory pattern
4. Record registry
5. (Optional) Decorator-based generator

**Tasks**:
- [ ] Port DbRecord class
- [ ] Implement Proxy-based typed access
- [ ] Port record factory pattern
- [ ] Implement record registry
- [ ] Add system column access
- [ ] Add fileset field access
- [ ] (Optional) Create decorator-based generator package
- [ ] Write DbRecord tests

### Phase 9: Error Handling & Utilities (Week 14)

**Goals**: Exception system and utilities

**Deliverables**:
1. Database exception types
2. SQLite error mapping
3. Utility functions

**Tasks**:
- [ ] Port key exception types (simplified)
- [ ] Implement SQLite error mapping
- [ ] Port SQL escaping utilities
- [ ] Add value serialization
- [ ] Write error handling tests
- [ ] Write utility tests

### Phase 10: Task Scheduling (Week 15)

**Goals**: Database maintenance

**Deliverables**:
1. Task scheduler
2. Cleanup tasks

**Tasks**:
- [ ] Port task scheduler
- [ ] Implement maintenance tasks
- [ ] Add scheduling configuration
- [ ] Write scheduler tests

### Phase 11: Testing & Documentation (Week 16-17)

**Goals**: Comprehensive tests and docs

**Deliverables**:
1. Full test coverage
2. API documentation
3. Usage guides
4. Migration guide

**Tasks**:
- [ ] Write integration tests
- [ ] Add performance benchmarks
- [ ] Generate API docs with TypeDoc
- [ ] Write getting started guide
- [ ] Write schema definition guide
- [ ] Write migration guide
- [ ] Write streaming queries guide
- [ ] Write offline sync guide
- [ ] Write migration from Dart guide
- [ ] Create troubleshooting guide

### Phase 12: Examples & Demos (Week 18-19)

**Goals**: Real-world examples

**Deliverables**:
1. Basic CRUD example
2. Streaming queries example
3. Offline sync example
4. PWA demo app
5. Capacitor mobile app

**Tasks**:
- [ ] Create basic CRUD example
- [ ] Create streaming queries example
- [ ] Create offline sync example
- [ ] Build PWA demo application
- [ ] Build Capacitor mobile demo
- [ ] Deploy PWA demo
- [ ] Write example documentation

### Phase 13: Polish & Release (Week 20)

**Goals**: Production-ready release

**Deliverables**:
1. Published npm package
2. Documentation website
3. Release announcement

**Tasks**:
- [ ] Code review and refactoring
- [ ] Performance optimization
- [ ] Bundle size optimization
- [ ] Browser compatibility testing
- [ ] Mobile testing (Capacitor)
- [ ] Final documentation review
- [ ] Set up documentation website
- [ ] Publish to npm
- [ ] Create release announcement
- [ ] Share with community

## Generator Package Analysis

### Current Dart Generator Purpose

The `declarative_sqlite_generator` package solves Dart-specific problems:

1. **No Reflection**: Dart doesn't support runtime reflection
2. **Typed Accessors**: Generates getters/setters for DbRecord fields
3. **Factory Registration**: Auto-registers record factories

**Example Generated Code (Dart)**:
```dart
// Input
@GenerateDbRecord('users')
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);
}

// Generated in user.db.dart
extension UserExtension on User {
  String get name => getValue('name')!;
  set name(String value) => setValue('name', value);
  
  int get age => getValue('age')!;
  set age(int value) => setValue('age', value);
}
```

### TypeScript Alternatives

#### Option 1: No Generator (Proxy-Based)

**Pros**:
- Zero build step
- Immediate feedback
- Simpler development
- Smaller dependency footprint

**Cons**:
- Slightly less IDE support
- Minimal runtime overhead (negligible)

**Implementation**:
```typescript
class DbRecord<T extends Record<string, any>> {
  constructor(private db: DeclarativeDatabase, private tableName: string) {
    return new Proxy(this, {
      get(target, prop: string) {
        if (prop in target) return target[prop];
        return target.getValue(prop);
      },
      set(target, prop: string, value) {
        if (prop in target) {
          target[prop] = value;
        } else {
          target.setValue(prop, value);
        }
        return true;
      }
    }) as DbRecord<T> & T;
  }
}

// Usage
interface UserData {
  name: string;
  age: number;
}

const user = db.createRecord<UserData>('users');
user.name = 'Alice';  // Type-safe!
console.log(user.age);  // Type-checked!
```

#### Option 2: Decorator-Based Generator (Optional)

**Pros**:
- Explicit schema definition
- Can generate schema from decorators
- Familiar to developers from TypeORM, etc.

**Cons**:
- Requires build step (tsc)
- More boilerplate
- Extra complexity

**Implementation**:
```typescript
// packages/generator/src/decorator.ts
import 'reflect-metadata';

export function Table(name: string) {
  return function <T extends { new (...args: any[]): {} }>(constructor: T) {
    Reflect.defineMetadata('table:name', name, constructor);
    return constructor;
  };
}

export function Column(type: string, options?: ColumnOptions) {
  return function (target: any, propertyKey: string) {
    const columns = Reflect.getMetadata('table:columns', target.constructor) || [];
    columns.push({ name: propertyKey, type, options });
    Reflect.defineMetadata('table:columns', columns, target.constructor);
  };
}

// Usage
@Table('users')
class User extends DbRecord {
  @Column('guid')
  @PrimaryKey()
  id!: string;
  
  @Column('text')
  name!: string;
  
  @Column('integer')
  age!: number;
}

// Extract schema at runtime
const schema = SchemaExtractor.extractFromClass(User);
```

### Recommendation: Hybrid Approach

**Core Package**: Use Proxy-based approach (no generator required)
- Zero build step for most users
- TypeScript types provide safety
- Simpler onboarding

**Optional Generator Package**: Provide decorator-based approach
- For users who prefer explicit schemas
- Can generate schema from decorators
- Dev dependency only
- Not required for runtime

**Package Structure**:
```
@declarative-sqlite/core        # No generator dependency
@declarative-sqlite/generator   # Optional, for decorators
```

**Migration Path**:
- Start with core (no generator)
- Add generator later if user demand exists
- Keep generator optional and separate

## Technology Decisions Summary

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **SQLite Backend** | wa-sqlite (primary), Capacitor SQLite (mobile) | Cross-platform, works in browser and Node |
| **Build Tool** | Vite | Fast, modern, great DX |
| **Test Framework** | Vitest | Fast, compatible with Vite, great API |
| **Package Manager** | pnpm | Fast, efficient, workspace support |
| **Streaming** | RxJS | Industry standard, powerful operators |
| **Code Generation** | Optional (Proxy-based primary) | Reduce complexity, zero build step |
| **Type System** | TypeScript Strict Mode | Maximum type safety |
| **Module System** | ESM (with CJS compat) | Modern, tree-shakeable |
| **Error Handling** | Exceptions (with Result option) | Consistent API, familiar pattern |
| **Documentation** | TypeDoc + Markdown | Auto-generated API + guides |

## Risk Analysis & Mitigation

### Risk 1: SQLite Compatibility

**Risk**: Different SQLite backends have different APIs

**Mitigation**: 
- Abstract SQLite operations through adapter interface
- Test against multiple backends
- Document backend-specific limitations
- Provide migration guides between backends

### Risk 2: Performance

**Risk**: TypeScript/JavaScript may be slower than Dart/native

**Mitigation**:
- Use WebAssembly SQLite (compiled C code, fast)
- Benchmark against acceptable thresholds
- Optimize critical paths (query execution, streaming)
- Consider worker threads for heavy operations

### Risk 3: Bundle Size

**Risk**: Large bundle size for web applications

**Mitigation**:
- Tree-shakeable ESM modules
- Optional features as separate imports
- Code splitting for large features
- Monitor bundle size in CI
- Target <50KB gzipped for core

### Risk 4: Browser Compatibility

**Risk**: Some features may not work in all browsers

**Mitigation**:
- Use widely supported APIs
- Polyfills for older browsers (if needed)
- Document browser requirements
- Test on major browsers (Chrome, Firefox, Safari, Edge)

### Risk 5: Migration Complexity

**Risk**: Migration from Dart may be complex for users

**Mitigation**:
- Provide detailed migration guide
- API compatibility layer (where possible)
- Migration examples for common patterns
- Community support and documentation

### Risk 6: Feature Parity

**Risk**: Missing features from Dart version

**Mitigation**:
- Prioritize core features first
- Document feature roadmap
- Add features incrementally
- Get community feedback

## Success Criteria

### Phase 1-6 (MVP)
- [ ] Schema definition works
- [ ] Auto-migration works
- [ ] CRUD operations work
- [ ] Basic queries work
- [ ] Tests pass
- [ ] Works in browser (wa-sqlite)

### Phase 7-10 (Feature Complete)
- [ ] Streaming queries work
- [ ] HLC and LWW work
- [ ] Dirty row tracking works
- [ ] File management works
- [ ] Works in Capacitor app

### Phase 11-13 (Production Ready)
- [ ] Documentation complete
- [ ] Examples working
- [ ] PWA demo deployed
- [ ] Published to npm
- [ ] Bundle size <50KB gzipped (core)
- [ ] Test coverage >80%

## Timeline Estimate

**Total**: ~20 weeks (5 months) for full migration

**Breakdown**:
- Foundation: 1 week
- Core features (Schema, Migration, CRUD): 6 weeks
- Advanced features (Sync, Files, Streaming): 6 weeks
- Polish (DbRecord, Errors, Scheduling): 3 weeks
- Testing, Docs, Examples: 4 weeks

**Notes**:
- Assumes 1 full-time developer
- Can be parallelized with multiple developers
- Can be phased (MVP in 8 weeks, full in 20)

## Open Questions

1. **Should we support transactions?**
   - Dart version explicitly doesn't support them
   - TypeScript version could add support
   - Trade-off: complexity vs functionality

2. **RxJS as peer dependency?**
   - Reduces bundle size
   - Requires users to install RxJS
   - Alternative: build minimal Observable implementation

3. **Support Node.js only features?**
   - Filesystem access in Node.js
   - Worker threads for background processing
   - Different from browser-only features

4. **Versioning strategy?**
   - Start at 0.1.0 or 1.0.0?
   - Semantic versioning
   - Breaking changes policy

5. **Capacitor SQLite vs wa-sqlite priority?**
   - Which to implement first?
   - Both eventually, but order matters

## Next Steps

1. **Validate Plan**: Review with stakeholders
2. **Set Up Repository**: Create TypeScript monorepo
3. **Proof of Concept**: Build minimal schema + migration
4. **Community Feedback**: Share PoC, gather input
5. **Begin Phase 1**: Start foundation setup

## Appendix A: API Comparison

### Schema Definition

**Dart**:
```dart
final schema = SchemaBuilder()
  .table('users', (table) {
    table.guid('id');
    table.text('name').notNull('');
    table.integer('age').notNull(0);
    table.key(['id']).primary();
  })
  .build();
```

**TypeScript (Fluent)**:
```typescript
const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id');
    t.text('name').notNull('');
    t.integer('age').notNull(0);
    t.key('id').primary();
  })
  .build();
```

**TypeScript (Object)**:
```typescript
const schema = defineSchema({
  users: {
    id: { type: 'guid', primary: true },
    name: { type: 'text', notNull: true, default: '' },
    age: { type: 'integer', notNull: true, default: 0 }
  }
});
```

### CRUD Operations

**Dart**:
```dart
// Insert
final id = await db.insert('users', {
  'name': 'Alice',
  'age': 30,
});

// Query
final users = await db.queryMaps((q) => q
  .from('users')
  .where(RawSqlWhereClause('age > ?', [18]))
);

// Update
await db.update('users', {'age': 31},
  where: 'name = ?',
  whereArgs: ['Alice']
);
```

**TypeScript**:
```typescript
// Insert
const id = await db.insert('users', {
  name: 'Alice',
  age: 30
});

// Query
const users = await db.query(q => q
  .from('users')
  .where('age', '>', 18)
);

// Update
await db.update('users', { age: 31 },
  { where: 'name = ?', args: ['Alice'] }
);
```

### Streaming Queries

**Dart**:
```dart
final stream = db.stream<Map<String, Object?>>(
  (q) => q.from('users'),
  (row) => row,
);

stream.listen((users) {
  print('Users: ${users.length}');
});
```

**TypeScript**:
```typescript
const users$ = db.stream(q => q.from('users'));

users$.subscribe(users => {
  console.log(`Users: ${users.length}`);
});

// With RxJS operators
users$
  .pipe(
    map(users => users.length),
    distinctUntilChanged()
  )
  .subscribe(count => console.log(`Count: ${count}`));
```

### Typed Records

**Dart** (with generator):
```dart
@GenerateDbRecord('users')
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase db)
      : super(data, 'users', db);
}

// Generated extension provides:
final user = User({}, db);
user.name = 'Alice';  // Type-safe
```

**TypeScript** (with Proxy):
```typescript
interface UserData {
  name: string;
  age: number;
}

const user = db.createRecord<UserData>('users');
user.name = 'Alice';  // Type-safe, no codegen!
```

## Appendix B: File Size Estimates

| Component | Estimated Size (Gzipped) |
|-----------|--------------------------|
| Schema System | ~8 KB |
| Migration Engine | ~6 KB |
| Database Operations | ~10 KB |
| Query Builder | ~5 KB |
| Sync (HLC, LWW, Dirty) | ~7 KB |
| File Management | ~4 KB |
| Streaming Queries | ~6 KB |
| DbRecord System | ~3 KB |
| Error Handling | ~3 KB |
| Utilities | ~2 KB |
| **Core Total** | **~45-50 KB** |
| RxJS (peer dep) | ~20 KB |
| wa-sqlite WASM | ~400 KB (cached) |

**Note**: WASM SQLite is large but cached by browser, loaded once

## Appendix C: Dart vs TypeScript Feature Matrix

| Feature | Dart | TypeScript | Notes |
|---------|------|------------|-------|
| Schema Definition | ✅ | ✅ | Both fluent builders |
| Auto Migration | ✅ | ✅ | Direct port |
| CRUD Operations | ✅ | ✅ | Similar API |
| Streaming Queries | ✅ | ✅ | TS uses RxJS |
| HLC Timestamps | ✅ | ✅ | Direct port |
| LWW Columns | ✅ | ✅ | Direct port |
| Dirty Row Tracking | ✅ | ✅ | Direct port |
| File Management | ✅ | ✅ | Direct port |
| DbRecord | ✅ | ✅ | TS uses Proxy |
| Code Generation | Required | Optional | TS has reflection |
| Transactions | ❌ | ? | Could add in TS |
| Flutter Widgets | ✅ | N/A | Web components instead |
| Type Safety | ✅ | ✅ | Both strong typing |
| Runtime Reflection | ❌ | ✅ | TS advantage |

---

**Document Version**: 1.0  
**Last Updated**: 2024-12-06  
**Author**: Migration Planning Team  
**Status**: Draft for Review
