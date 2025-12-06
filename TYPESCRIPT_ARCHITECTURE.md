# TypeScript Architecture Design for declarative_sqlite

## Overview

This document provides detailed technical architecture for the TypeScript implementation of declarative_sqlite, focusing on key design decisions, implementation patterns, and code examples.

## Core Design Principles

1. **Zero Runtime Overhead**: Minimize abstraction layers that add runtime cost
2. **Tree-Shakeable**: Every feature should be independently importable
3. **Type-Safe by Default**: Leverage TypeScript's type system maximally
4. **Browser-First, Node-Compatible**: Primary target is browser/PWA, with Node.js support
5. **No Build Dependencies for Core Features**: Code generation should be optional

## SQLite Adapter Layer

### Interface Design

```typescript
// packages/core/src/adapters/adapter.interface.ts

/**
 * Result from a SQL statement execution that modifies data
 */
export interface RunResult {
  /** Number of rows modified */
  changes: number;
  /** Last inserted row ID (if applicable) */
  lastInsertRowid: number | bigint;
}

/**
 * Prepared statement interface for parameterized queries
 */
export interface PreparedStatement {
  /**
   * Execute statement and return results as array of objects
   * @param params - Positional parameters for the query
   */
  all<T = any>(...params: any[]): Promise<T[]>;
  
  /**
   * Execute statement and return first result
   * @param params - Positional parameters for the query
   */
  get<T = any>(...params: any[]): Promise<T | undefined>;
  
  /**
   * Execute statement without returning results
   * @param params - Positional parameters for the query
   */
  run(...params: any[]): Promise<RunResult>;
  
  /**
   * Finalize/close the prepared statement
   */
  finalize(): Promise<void>;
}

/**
 * Main SQLite adapter interface
 * Abstraction layer to support multiple SQLite implementations
 */
export interface SQLiteAdapter {
  /**
   * Open/initialize the database
   * @param path - Database file path (or ':memory:' for in-memory)
   */
  open(path: string): Promise<void>;
  
  /**
   * Close the database connection
   */
  close(): Promise<void>;
  
  /**
   * Execute SQL without returning results (for DDL, etc.)
   * @param sql - SQL statement to execute
   */
  exec(sql: string): Promise<void>;
  
  /**
   * Prepare a SQL statement for execution
   * @param sql - SQL statement with ? placeholders
   */
  prepare(sql: string): PreparedStatement;
  
  /**
   * Execute multiple statements in a transaction
   * Automatically commits on success, rolls back on error
   * @param callback - Function containing transaction logic
   */
  transaction<T>(callback: (tx: SQLiteAdapter) => Promise<T>): Promise<T>;
  
  /**
   * Check if database is currently open
   */
  isOpen(): boolean;
}
```

### wa-sqlite Implementation

```typescript
// packages/core/src/adapters/wa-sqlite.adapter.ts

import * as SQLite from 'wa-sqlite';
import { IDBBatchAtomicVFS } from 'wa-sqlite/src/examples/IDBBatchAtomicVFS.js';
import type { SQLiteAdapter, PreparedStatement, RunResult } from './adapter.interface';

export class WaSqliteAdapter implements SQLiteAdapter {
  private sqlite: SQLite.API | null = null;
  private db: number | null = null;
  private vfs: IDBBatchAtomicVFS | null = null;
  
  async open(path: string): Promise<void> {
    // Initialize SQLite WASM module
    const module = await SQLite.default();
    this.sqlite = SQLite.Factory(module);
    
    // Create VFS for persistence (IndexedDB-based)
    if (path !== ':memory:') {
      this.vfs = await IDBBatchAtomicVFS.create('declarative-sqlite-vfs', module);
      this.sqlite.vfs_register(this.vfs, true);
    }
    
    // Open database
    this.db = await this.sqlite.open_v2(
      path,
      SQLite.SQLITE_OPEN_READWRITE | SQLite.SQLITE_OPEN_CREATE
    );
  }
  
  async close(): Promise<void> {
    if (this.db !== null && this.sqlite) {
      await this.sqlite.close(this.db);
      this.db = null;
      this.sqlite = null;
    }
  }
  
  async exec(sql: string): Promise<void> {
    if (!this.sqlite || this.db === null) {
      throw new Error('Database not open');
    }
    
    await this.sqlite.exec(this.db, sql);
  }
  
  prepare(sql: string): PreparedStatement {
    if (!this.sqlite || this.db === null) {
      throw new Error('Database not open');
    }
    
    const stmt = this.sqlite.prepare_v2(this.db, sql);
    if (!stmt) {
      throw new Error(`Failed to prepare statement: ${sql}`);
    }
    
    return new WaSqlitePreparedStatement(this.sqlite, this.db, stmt);
  }
  
  async transaction<T>(callback: (tx: SQLiteAdapter) => Promise<T>): Promise<T> {
    await this.exec('BEGIN TRANSACTION');
    try {
      const result = await callback(this);
      await this.exec('COMMIT');
      return result;
    } catch (error) {
      await this.exec('ROLLBACK');
      throw error;
    }
  }
  
  isOpen(): boolean {
    return this.db !== null && this.sqlite !== null;
  }
}

class WaSqlitePreparedStatement implements PreparedStatement {
  constructor(
    private sqlite: SQLite.API,
    private db: number,
    private stmt: number
  ) {}
  
  async all<T = any>(...params: any[]): Promise<T[]> {
    // Bind parameters
    this.bindParams(params);
    
    // Collect all rows
    const results: T[] = [];
    const columns = this.sqlite.column_names(this.stmt);
    
    while (await this.sqlite.step(this.stmt) === SQLite.SQLITE_ROW) {
      const row: any = {};
      for (let i = 0; i < columns.length; i++) {
        row[columns[i]] = this.sqlite.column(this.stmt, i);
      }
      results.push(row);
    }
    
    await this.sqlite.reset(this.stmt);
    return results;
  }
  
  async get<T = any>(...params: any[]): Promise<T | undefined> {
    const results = await this.all<T>(...params);
    return results[0];
  }
  
  async run(...params: any[]): Promise<RunResult> {
    this.bindParams(params);
    await this.sqlite.step(this.stmt);
    await this.sqlite.reset(this.stmt);
    
    return {
      changes: this.sqlite.changes(this.db),
      lastInsertRowid: this.sqlite.last_insert_rowid(this.db)
    };
  }
  
  async finalize(): Promise<void> {
    await this.sqlite.finalize(this.stmt);
  }
  
  private bindParams(params: any[]): void {
    for (let i = 0; i < params.length; i++) {
      const value = params[i];
      const index = i + 1; // SQLite uses 1-based indexing
      
      if (value === null || value === undefined) {
        this.sqlite.bind_null(this.stmt, index);
      } else if (typeof value === 'number') {
        if (Number.isInteger(value)) {
          this.sqlite.bind_int(this.stmt, index, value);
        } else {
          this.sqlite.bind_double(this.stmt, index, value);
        }
      } else if (typeof value === 'string') {
        this.sqlite.bind_text(this.stmt, index, value);
      } else if (value instanceof Uint8Array) {
        this.sqlite.bind_blob(this.stmt, index, value);
      } else {
        // Convert to JSON string for objects
        this.sqlite.bind_text(this.stmt, index, JSON.stringify(value));
      }
    }
  }
}
```

### Capacitor SQLite Adapter

```typescript
// packages/core/src/adapters/capacitor.adapter.ts

import { CapacitorSQLite, SQLiteDBConnection } from '@capacitor-community/sqlite';
import type { SQLiteAdapter, PreparedStatement, RunResult } from './adapter.interface';

export class CapacitorSqliteAdapter implements SQLiteAdapter {
  private db: SQLiteDBConnection | null = null;
  private dbName: string = '';
  
  async open(path: string): Promise<void> {
    // Extract database name from path
    this.dbName = path === ':memory:' ? 'memory' : path.split('/').pop() || 'database';
    
    // Create connection
    const result = await CapacitorSQLite.createConnection({
      database: this.dbName,
      version: 1,
      encrypted: false,
      mode: 'no-encryption'
    });
    
    this.db = result.db;
    await this.db.open();
  }
  
  async close(): Promise<void> {
    if (this.db) {
      await this.db.close();
      await CapacitorSQLite.closeConnection({ database: this.dbName });
      this.db = null;
    }
  }
  
  async exec(sql: string): Promise<void> {
    if (!this.db) throw new Error('Database not open');
    await this.db.execute(sql);
  }
  
  prepare(sql: string): PreparedStatement {
    if (!this.db) throw new Error('Database not open');
    return new CapacitorPreparedStatement(this.db, sql);
  }
  
  async transaction<T>(callback: (tx: SQLiteAdapter) => Promise<T>): Promise<T> {
    if (!this.db) throw new Error('Database not open');
    
    await this.db.execute('BEGIN TRANSACTION');
    try {
      const result = await callback(this);
      await this.db.execute('COMMIT');
      return result;
    } catch (error) {
      await this.db.execute('ROLLBACK');
      throw error;
    }
  }
  
  isOpen(): boolean {
    return this.db !== null;
  }
}

class CapacitorPreparedStatement implements PreparedStatement {
  constructor(
    private db: SQLiteDBConnection,
    private sql: string
  ) {}
  
  async all<T = any>(...params: any[]): Promise<T[]> {
    const result = await this.db.query(this.sql, params);
    return result.values || [];
  }
  
  async get<T = any>(...params: any[]): Promise<T | undefined> {
    const results = await this.all<T>(...params);
    return results[0];
  }
  
  async run(...params: any[]): Promise<RunResult> {
    const result = await this.db.run(this.sql, params);
    return {
      changes: result.changes?.changes || 0,
      lastInsertRowid: result.changes?.lastId || 0
    };
  }
  
  async finalize(): Promise<void> {
    // Capacitor doesn't require explicit finalization
  }
}
```

## Schema System with Type Safety

### Schema Builder with Generics

```typescript
// packages/core/src/schema/builders/schema-builder.ts

import type { Schema, DbTable, DbView } from '../types';
import { TableBuilder } from './table-builder';
import { ViewBuilder } from './view-builder';
import { createSystemTables } from '../system-tables';

/**
 * Fluent builder for defining database schemas
 */
export class SchemaBuilder {
  private tables: Map<string, TableBuilder<any>> = new Map();
  private views: Map<string, ViewBuilder<any>> = new Map();
  
  /**
   * Define a table in the schema
   * @param name - Table name
   * @param build - Table definition callback
   */
  table<T extends Record<string, any>>(
    name: string,
    build: (table: TableBuilder<T>) => void
  ): this {
    const builder = new TableBuilder<T>(name);
    build(builder);
    this.tables.set(name, builder);
    return this;
  }
  
  /**
   * Define a view in the schema
   * @param name - View name
   * @param build - View definition callback
   */
  view<T extends Record<string, any>>(
    name: string,
    build: (view: ViewBuilder<T>) => void
  ): this {
    const builder = new ViewBuilder<T>(name);
    build(builder);
    this.views.set(name, builder);
    return this;
  }
  
  /**
   * Build the final schema
   */
  build(): Schema {
    // Build user tables
    const userTables = Array.from(this.tables.values())
      .filter(t => !t.name.startsWith('__'))
      .map(t => t.build());
    
    // Add system tables
    const systemTables = createSystemTables();
    
    // Build views
    const views = Array.from(this.views.values()).map(v => v.build());
    
    return {
      tables: [...userTables, ...systemTables],
      views,
      version: this.computeSchemaVersion([...userTables, ...systemTables], views)
    };
  }
  
  private computeSchemaVersion(tables: DbTable[], views: DbView[]): string {
    // Create deterministic hash of schema
    const schemaString = JSON.stringify({
      tables: tables.map(t => ({ name: t.name, columns: t.columns, keys: t.keys })),
      views: views.map(v => ({ name: v.name, sql: v.sql }))
    });
    
    // Simple hash function (in production, use crypto.subtle.digest)
    let hash = 0;
    for (let i = 0; i < schemaString.length; i++) {
      hash = ((hash << 5) - hash) + schemaString.charCodeAt(i);
      hash = hash & hash; // Convert to 32-bit integer
    }
    
    return Math.abs(hash).toString(36);
  }
}
```

### Table Builder with Type Tracking

```typescript
// packages/core/src/schema/builders/table-builder.ts

import type { DbTable, DbColumn, DbKey } from '../types';
import { 
  TextColumnBuilder,
  IntegerColumnBuilder,
  RealColumnBuilder,
  GuidColumnBuilder,
  DateColumnBuilder,
  FilesetColumnBuilder
} from './column-builders';
import { KeyBuilder } from './key-builder';

/**
 * Fluent builder for defining database tables
 * Generic T tracks the shape of records in this table
 */
export class TableBuilder<T extends Record<string, any>> {
  private columns: DbColumn[] = [];
  private keys: DbKey[] = [];
  
  constructor(public readonly name: string) {
    // Add system columns automatically
    this.addSystemColumns();
  }
  
  /**
   * Add a text column
   */
  text<K extends keyof T>(name: K): TextColumnBuilder<T, K> {
    return this.addColumn(new TextColumnBuilder<T, K>(name as string));
  }
  
  /**
   * Add an integer column
   */
  integer<K extends keyof T>(name: K): IntegerColumnBuilder<T, K> {
    return this.addColumn(new IntegerColumnBuilder<T, K>(name as string));
  }
  
  /**
   * Add a real (float) column
   */
  real<K extends keyof T>(name: K): RealColumnBuilder<T, K> {
    return this.addColumn(new RealColumnBuilder<T, K>(name as string));
  }
  
  /**
   * Add a GUID column
   */
  guid<K extends keyof T>(name: K): GuidColumnBuilder<T, K> {
    return this.addColumn(new GuidColumnBuilder<T, K>(name as string));
  }
  
  /**
   * Add a date column
   */
  date<K extends keyof T>(name: K): DateColumnBuilder<T, K> {
    return this.addColumn(new DateColumnBuilder<T, K>(name as string));
  }
  
  /**
   * Add a fileset column
   */
  fileset<K extends keyof T>(name: K): FilesetColumnBuilder<T, K> {
    return this.addColumn(new FilesetColumnBuilder<T, K>(name as string));
  }
  
  /**
   * Define a key (primary, unique, or index)
   */
  key<K extends keyof T>(...columnNames: K[]): KeyBuilder<T> {
    const builder = new KeyBuilder<T>(columnNames.map(c => c as string));
    this.keys.push(builder.build());
    return builder;
  }
  
  /**
   * Build the final table definition
   */
  build(): DbTable {
    return {
      name: this.name,
      columns: this.columns,
      keys: this.keys,
      isSystem: this.name.startsWith('__')
    };
  }
  
  private addColumn<B extends { build(): DbColumn }>(builder: B): B {
    // Register callback to add column when built
    const originalBuild = builder.build.bind(builder);
    builder.build = () => {
      const column = originalBuild();
      this.columns.push(column);
      return column;
    };
    return builder;
  }
  
  private addSystemColumns(): void {
    // system_id: Auto-generated UUID primary key
    new GuidColumnBuilder('system_id')
      .notNull('00000000-0000-0000-0000-000000000000')
      .build();
    
    // system_created_at: HLC timestamp of creation
    new TextColumnBuilder('system_created_at')
      .notNull('')
      .build();
    
    // system_version: HLC timestamp of last modification
    new TextColumnBuilder('system_version')
      .notNull('')
      .build();
  }
}
```

### Column Builders

```typescript
// packages/core/src/schema/builders/column-builders/base-column-builder.ts

import type { DbColumn, ColumnType } from '../../types';

/**
 * Base class for column builders
 */
export abstract class BaseColumnBuilder<
  T extends Record<string, any>,
  K extends keyof T,
  TValue = T[K]
> {
  protected _notNull: boolean = false;
  protected _defaultValue?: TValue;
  protected _defaultFn?: () => TValue;
  protected _lww: boolean = false;
  protected _maxLength?: number;
  
  constructor(
    protected name: string,
    protected type: ColumnType
  ) {}
  
  /**
   * Mark column as NOT NULL with default value
   */
  notNull(defaultValue: TValue | (() => TValue)): this {
    this._notNull = true;
    
    if (typeof defaultValue === 'function') {
      this._defaultFn = defaultValue as () => TValue;
    } else {
      this._defaultValue = defaultValue;
    }
    
    return this;
  }
  
  /**
   * Enable Last-Write-Wins conflict resolution for this column
   * Creates an associated __hlc column automatically
   */
  lww(): this {
    this._lww = true;
    return this;
  }
  
  /**
   * Build the column definition
   */
  build(): DbColumn {
    return {
      name: this.name,
      type: this.type,
      notNull: this._notNull,
      defaultValue: this._defaultValue,
      defaultFn: this._defaultFn,
      lww: this._lww,
      maxLength: this._maxLength
    };
  }
}

// packages/core/src/schema/builders/column-builders/text-column-builder.ts

export class TextColumnBuilder<
  T extends Record<string, any>,
  K extends keyof T
> extends BaseColumnBuilder<T, K, string> {
  constructor(name: string) {
    super(name, 'TEXT');
  }
  
  /**
   * Set maximum length for text column
   */
  maxLength(length: number): this {
    this._maxLength = length;
    return this;
  }
}

// Similar builders for Integer, Real, GUID, Date, Fileset...
```

## Proxy-Based DbRecord System

### Type-Safe Record Access

```typescript
// packages/core/src/records/db-record.ts

import type { DeclarativeDatabase } from '../database/declarative-database';
import type { FilesetField } from '../files/fileset-field';

/**
 * Base class for database records with type-safe property access
 * Uses Proxy to enable direct property access without code generation
 */
export class DbRecord<T extends Record<string, any>> {
  private data: Map<string, any>;
  
  constructor(
    private db: DeclarativeDatabase,
    private tableName: string,
    initialData: Partial<T> = {}
  ) {
    this.data = new Map(Object.entries(initialData));
    
    // Return Proxy for transparent property access
    return new Proxy(this, {
      get(target, prop: string | symbol) {
        // Allow access to methods and system properties
        if (typeof prop === 'symbol' || prop in target) {
          return (target as any)[prop];
        }
        
        // Intercept property access
        return target.getValue(prop);
      },
      
      set(target, prop: string | symbol, value: any) {
        // Allow setting methods and system properties
        if (typeof prop === 'symbol' || prop in target) {
          (target as any)[prop] = value;
          return true;
        }
        
        // Intercept property assignment
        target.setValue(prop, value);
        return true;
      },
      
      has(target, prop: string | symbol) {
        if (typeof prop === 'symbol') return prop in target;
        return target.hasValue(prop) || prop in target;
      },
      
      ownKeys(target) {
        return Array.from(target.data.keys());
      },
      
      getOwnPropertyDescriptor(target, prop: string | symbol) {
        if (typeof prop === 'symbol') return undefined;
        
        if (target.hasValue(prop)) {
          return {
            enumerable: true,
            configurable: true,
            value: target.getValue(prop)
          };
        }
        return undefined;
      }
    }) as DbRecord<T> & T;
  }
  
  /**
   * Get value for a column
   */
  protected getValue(key: string): any {
    return this.data.get(key);
  }
  
  /**
   * Set value for a column
   */
  protected setValue(key: string, value: any): void {
    this.data.set(key, value);
  }
  
  /**
   * Check if a value exists
   */
  protected hasValue(key: string): boolean {
    return this.data.has(key);
  }
  
  /**
   * Get system_id (internal primary key)
   */
  get systemId(): string {
    return this.getValue('system_id');
  }
  
  /**
   * Get creation timestamp
   */
  get systemCreatedAt(): string {
    return this.getValue('system_created_at');
  }
  
  /**
   * Get last modification timestamp
   */
  get systemVersion(): string {
    return this.getValue('system_version');
  }
  
  /**
   * Get fileset field for a fileset column
   */
  getFilesetField(columnName: string): FilesetField {
    return new FilesetField(this.db, this.tableName, this.systemId, columnName);
  }
  
  /**
   * Convert record to plain object
   */
  toObject(): T {
    return Object.fromEntries(this.data) as T;
  }
  
  /**
   * Save record to database (insert or update)
   */
  async save(): Promise<void> {
    if (this.systemId) {
      // Update existing record
      await this.db.update(this.tableName, this.toObject(), {
        where: 'system_id = ?',
        args: [this.systemId]
      });
    } else {
      // Insert new record
      const systemId = await this.db.insert(this.tableName, this.toObject());
      this.setValue('system_id', systemId);
    }
  }
  
  /**
   * Delete record from database
   */
  async delete(): Promise<void> {
    if (!this.systemId) {
      throw new Error('Cannot delete record without system_id');
    }
    
    await this.db.delete(this.tableName, {
      where: 'system_id = ?',
      args: [this.systemId]
    });
  }
}
```

### Usage Example

```typescript
// Define table type
interface User {
  id: string;
  name: string;
  age: number;
  email: string;
}

// Create schema
const schema = new SchemaBuilder()
  .table<User>('users', t => {
    t.guid('id');
    t.text('name').notNull('');
    t.integer('age').notNull(0);
    t.text('email').notNull('');
    t.key('id').primary();
  })
  .build();

// Open database
const db = new DeclarativeDatabase({
  schema,
  adapter: new WaSqliteAdapter()
});
await db.open('app.db');

// Create typed record - NO CODE GENERATION NEEDED!
const user = db.createRecord<User>('users');

// Type-safe property access
user.name = 'Alice';        // ✅ Type-safe
user.age = 30;              // ✅ Type-safe
user.email = 'a@example.com'; // ✅ Type-safe
// user.age = 'thirty';     // ❌ TypeScript error!

// Save to database
await user.save();

// Query returns typed records
const users = await db.queryRecords<User>('users', q => 
  q.where('age', '>', 18)
);

for (const u of users) {
  console.log(u.name);  // ✅ Type-safe
  console.log(u.age);   // ✅ Type-safe
}
```

## Streaming Queries with RxJS

### StreamingQuery Implementation

```typescript
// packages/core/src/streaming/streaming-query.ts

import { Observable, Subject, Subscription } from 'rxjs';
import { distinctUntilChanged, shareReplay } from 'rxjs/operators';
import type { DeclarativeDatabase } from '../database/declarative-database';
import type { QueryBuilder } from '../query/query-builder';
import { DependencyAnalyzer } from './dependency-analyzer';

/**
 * Represents a streaming query that emits updated results
 * when underlying data changes
 */
export class StreamingQuery<T> {
  private observable: Observable<T[]>;
  private dependencies: Set<string>;
  private subscription?: Subscription;
  
  constructor(
    private db: DeclarativeDatabase,
    private queryFn: (q: QueryBuilder<T>) => QueryBuilder<T>,
    private mapFn: (row: any) => T
  ) {
    // Analyze query dependencies
    const analyzer = new DependencyAnalyzer();
    const builder = this.queryFn(new QueryBuilder<T>());
    this.dependencies = analyzer.analyze(builder);
    
    // Create observable
    this.observable = new Observable<T[]>(subscriber => {
      // Execute query immediately
      this.executeQuery().then(
        results => subscriber.next(results),
        error => subscriber.error(error)
      );
      
      // Listen for changes to dependent tables
      const changeHandler = (tableName: string) => {
        if (this.dependencies.has(tableName)) {
          this.executeQuery().then(
            results => subscriber.next(results),
            error => subscriber.error(error)
          );
        }
      };
      
      this.db.on('dataChanged', changeHandler);
      
      // Cleanup
      return () => {
        this.db.off('dataChanged', changeHandler);
      };
    }).pipe(
      distinctUntilChanged((a, b) => {
        // Deep equality check
        return JSON.stringify(a) === JSON.stringify(b);
      }),
      shareReplay(1) // Cache latest result for new subscribers
    );
  }
  
  /**
   * Subscribe to query results
   */
  subscribe(
    next?: (value: T[]) => void,
    error?: (error: any) => void,
    complete?: () => void
  ): Subscription {
    return this.observable.subscribe(next, error, complete);
  }
  
  /**
   * Get the RxJS Observable
   */
  asObservable(): Observable<T[]> {
    return this.observable;
  }
  
  /**
   * Execute the query and return results
   */
  private async executeQuery(): Promise<T[]> {
    const builder = this.queryFn(new QueryBuilder<T>());
    const rows = await this.db.query(builder);
    return rows.map(this.mapFn);
  }
}
```

### Usage Example

```typescript
// Simple streaming query
const users$ = db.stream<User>(
  q => q.from('users').where('age', '>', 18),
  row => row as User
);

users$.subscribe(users => {
  console.log(`${users.length} adult users`);
});

// With RxJS operators
import { map, filter, debounceTime } from 'rxjs/operators';

users$
  .pipe(
    map(users => users.filter(u => u.email.includes('@gmail.com'))),
    filter(users => users.length > 0),
    debounceTime(300),
    map(users => users.map(u => u.name))
  )
  .subscribe(names => {
    console.log('Gmail users:', names);
  });

// Combine multiple streams
import { combineLatest } from 'rxjs';

const posts$ = db.stream<Post>(q => q.from('posts'));

combineLatest([users$, posts$])
  .pipe(
    map(([users, posts]) => {
      // Join users and posts
      return users.map(user => ({
        user,
        posts: posts.filter(p => p.userId === user.id)
      }));
    })
  )
  .subscribe(userPosts => {
    console.log('Users with posts:', userPosts);
  });
```

## Hybrid Logical Clock (HLC) Implementation

### HLC Timestamp

```typescript
// packages/core/src/sync/hlc/hlc-timestamp.ts

/**
 * Hybrid Logical Clock timestamp
 * Format: <milliseconds>:<counter>:<nodeId>
 */
export class HlcTimestamp {
  constructor(
    public readonly milliseconds: number,
    public readonly counter: number,
    public readonly nodeId: string
  ) {}
  
  /**
   * Compare two HLC timestamps
   * Returns: -1 if this < other, 0 if equal, 1 if this > other
   */
  compare(other: HlcTimestamp): number {
    // Compare milliseconds first
    if (this.milliseconds < other.milliseconds) return -1;
    if (this.milliseconds > other.milliseconds) return 1;
    
    // Then counter
    if (this.counter < other.counter) return -1;
    if (this.counter > other.counter) return 1;
    
    // Then node ID (for total ordering)
    if (this.nodeId < other.nodeId) return -1;
    if (this.nodeId > other.nodeId) return 1;
    
    return 0;
  }
  
  /**
   * Check if this timestamp happened before another
   */
  isBefore(other: HlcTimestamp): boolean {
    return this.compare(other) < 0;
  }
  
  /**
   * Check if this timestamp happened after another
   */
  isAfter(other: HlcTimestamp): boolean {
    return this.compare(other) > 0;
  }
  
  /**
   * Convert to string format
   */
  toString(): string {
    return `${this.milliseconds}:${this.counter}:${this.nodeId}`;
  }
  
  /**
   * Parse HLC timestamp from string
   */
  static parse(str: string): HlcTimestamp {
    const parts = str.split(':');
    if (parts.length !== 3) {
      throw new Error(`Invalid HLC timestamp format: ${str}`);
    }
    
    return new HlcTimestamp(
      parseInt(parts[0], 10),
      parseInt(parts[1], 10),
      parts[2]
    );
  }
  
  /**
   * Create HLC timestamp from Date
   */
  static fromDate(date: Date, counter: number, nodeId: string): HlcTimestamp {
    return new HlcTimestamp(date.getTime(), counter, nodeId);
  }
}
```

### HLC Clock

```typescript
// packages/core/src/sync/hlc/hlc-clock.ts

import { HlcTimestamp } from './hlc-timestamp';
import { generateNodeId } from './node-id';

/**
 * Hybrid Logical Clock for generating causally-ordered timestamps
 */
export class HlcClock {
  private lastTimestamp: HlcTimestamp;
  private nodeId: string;
  
  constructor(nodeId?: string) {
    this.nodeId = nodeId || generateNodeId();
    this.lastTimestamp = new HlcTimestamp(0, 0, this.nodeId);
  }
  
  /**
   * Generate a new HLC timestamp
   * @param wallTime - Optional wall clock time (defaults to Date.now())
   */
  now(wallTime?: number): HlcTimestamp {
    const physicalTime = wallTime || Date.now();
    const lastMs = this.lastTimestamp.milliseconds;
    const lastCounter = this.lastTimestamp.counter;
    
    let newMs: number;
    let newCounter: number;
    
    if (physicalTime > lastMs) {
      // Physical time advanced, reset counter
      newMs = physicalTime;
      newCounter = 0;
    } else {
      // Physical time hasn't advanced (or went backwards), increment counter
      newMs = lastMs;
      newCounter = lastCounter + 1;
    }
    
    this.lastTimestamp = new HlcTimestamp(newMs, newCounter, this.nodeId);
    return this.lastTimestamp;
  }
  
  /**
   * Update clock based on received timestamp
   * Used when synchronizing with remote nodes
   */
  update(received: HlcTimestamp): HlcTimestamp {
    const physicalTime = Date.now();
    const lastMs = this.lastTimestamp.milliseconds;
    const lastCounter = this.lastTimestamp.counter;
    const receivedMs = received.milliseconds;
    const receivedCounter = received.counter;
    
    // Find max of physical, last, and received times
    const maxMs = Math.max(physicalTime, lastMs, receivedMs);
    
    let newCounter: number;
    
    if (maxMs === lastMs && maxMs === receivedMs) {
      // All three are equal, increment max counter
      newCounter = Math.max(lastCounter, receivedCounter) + 1;
    } else if (maxMs === lastMs) {
      // Last time is max, increment its counter
      newCounter = lastCounter + 1;
    } else if (maxMs === receivedMs) {
      // Received time is max, increment its counter
      newCounter = receivedCounter + 1;
    } else {
      // Physical time is max, reset counter
      newCounter = 0;
    }
    
    this.lastTimestamp = new HlcTimestamp(maxMs, newCounter, this.nodeId);
    return this.lastTimestamp;
  }
  
  /**
   * Get the current node ID
   */
  getNodeId(): string {
    return this.nodeId;
  }
}
```

### Node ID Generation

```typescript
// packages/core/src/sync/hlc/node-id.ts

/**
 * Generate a unique node ID for this device/instance
 * Uses browser fingerprinting + random component
 */
export function generateNodeId(): string {
  // Try to get from persistent storage
  if (typeof localStorage !== 'undefined') {
    const stored = localStorage.getItem('declarative-sqlite:node-id');
    if (stored) return stored;
  }
  
  // Generate new node ID
  const nodeId = createNodeId();
  
  // Store for future use
  if (typeof localStorage !== 'undefined') {
    localStorage.setItem('declarative-sqlite:node-id', nodeId);
  }
  
  return nodeId;
}

function createNodeId(): string {
  // Combine various sources for uniqueness
  const parts: string[] = [];
  
  // Browser/environment info
  if (typeof navigator !== 'undefined') {
    parts.push(navigator.userAgent);
    parts.push(navigator.language);
  }
  
  // Screen info
  if (typeof screen !== 'undefined') {
    parts.push(`${screen.width}x${screen.height}`);
    parts.push(`${screen.colorDepth}`);
  }
  
  // Timezone offset
  parts.push(`${new Date().getTimezoneOffset()}`);
  
  // Random component
  parts.push(crypto.randomUUID());
  
  // Hash to create short ID
  const combined = parts.join('|');
  return simpleHash(combined).toString(36);
}

function simpleHash(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash = hash & hash; // Convert to 32-bit integer
  }
  return Math.abs(hash);
}
```

## Migration System

### Schema Differ

```typescript
// packages/core/src/migration/differ.ts

import type { Schema, DbTable, DbColumn } from '../schema/types';

export interface SchemaDiff {
  tablesToCreate: DbTable[];
  tablesToDrop: string[];
  tablesToAlter: TableAlterationPlan[];
  viewsToCreate: string[];
  viewsToDrop: string[];
}

export interface TableAlterationPlan {
  tableName: string;
  columnsToAdd: DbColumn[];
  columnsToDrop: string[];
  columnsToModify: ColumnModification[];
  keysToAdd: DbKey[];
  keysToDrop: string[];
}

export interface ColumnModification {
  columnName: string;
  from: DbColumn;
  to: DbColumn;
}

/**
 * Compare two schemas and generate diff
 */
export class SchemaDiffer {
  diff(liveSchema: Schema, declarativeSchema: Schema): SchemaDiff {
    const diff: SchemaDiff = {
      tablesToCreate: [],
      tablesToDrop: [],
      tablesToAlter: [],
      viewsToCreate: [],
      viewsToDrop: []
    };
    
    // Find tables to create/drop/alter
    this.diffTables(liveSchema, declarativeSchema, diff);
    
    // Find views to create/drop
    this.diffViews(liveSchema, declarativeSchema, diff);
    
    return diff;
  }
  
  private diffTables(live: Schema, declarative: Schema, diff: SchemaDiff): void {
    const liveTables = new Map(live.tables.map(t => [t.name, t]));
    const declarativeTables = new Map(declarative.tables.map(t => [t.name, t]));
    
    // Tables to create (in declarative but not in live)
    for (const [name, table] of declarativeTables) {
      if (!liveTables.has(name)) {
        diff.tablesToCreate.push(table);
      }
    }
    
    // Tables to drop (in live but not in declarative)
    for (const name of liveTables.keys()) {
      if (!declarativeTables.has(name)) {
        diff.tablesToDrop.push(name);
      }
    }
    
    // Tables to alter (in both)
    for (const [name, liveTable] of liveTables) {
      const declTable = declarativeTables.get(name);
      if (declTable) {
        const alterPlan = this.diffTable(liveTable, declTable);
        if (this.hasChanges(alterPlan)) {
          diff.tablesToAlter.push(alterPlan);
        }
      }
    }
  }
  
  private diffTable(liveTable: DbTable, declTable: DbTable): TableAlterationPlan {
    const plan: TableAlterationPlan = {
      tableName: liveTable.name,
      columnsToAdd: [],
      columnsToDrop: [],
      columnsToModify: [],
      keysToAdd: [],
      keysToDrop: []
    };
    
    const liveColumns = new Map(liveTable.columns.map(c => [c.name, c]));
    const declColumns = new Map(declTable.columns.map(c => [c.name, c]));
    
    // Columns to add
    for (const [name, column] of declColumns) {
      if (!liveColumns.has(name)) {
        plan.columnsToAdd.push(column);
      }
    }
    
    // Columns to drop
    for (const name of liveColumns.keys()) {
      if (!declColumns.has(name)) {
        plan.columnsToDrop.push(name);
      }
    }
    
    // Columns to modify
    for (const [name, liveColumn] of liveColumns) {
      const declColumn = declColumns.get(name);
      if (declColumn && !this.columnsEqual(liveColumn, declColumn)) {
        plan.columnsToModify.push({
          columnName: name,
          from: liveColumn,
          to: declColumn
        });
      }
    }
    
    // TODO: Diff keys similarly
    
    return plan;
  }
  
  private columnsEqual(a: DbColumn, b: DbColumn): boolean {
    return a.type === b.type &&
           a.notNull === b.notNull &&
           a.defaultValue === b.defaultValue;
  }
  
  private hasChanges(plan: TableAlterationPlan): boolean {
    return plan.columnsToAdd.length > 0 ||
           plan.columnsToDrop.length > 0 ||
           plan.columnsToModify.length > 0 ||
           plan.keysToAdd.length > 0 ||
           plan.keysToDrop.length > 0;
  }
  
  private diffViews(live: Schema, declarative: Schema, diff: SchemaDiff): void {
    // TODO: Implement view diffing
  }
}
```

## Object-Based Schema Definition (Alternative)

For users who prefer object-based schema over builders:

```typescript
// packages/core/src/schema/define-schema.ts

import { SchemaBuilder } from './builders/schema-builder';
import type { Schema } from './types';

type ColumnDefinition = 
  | { type: 'text'; notNull?: boolean; default?: string; maxLength?: number; lww?: boolean }
  | { type: 'integer'; notNull?: boolean; default?: number; lww?: boolean }
  | { type: 'real'; notNull?: boolean; default?: number; lww?: boolean }
  | { type: 'guid'; notNull?: boolean; default?: string; lww?: boolean }
  | { type: 'date'; notNull?: boolean; default?: string; lww?: boolean }
  | { type: 'fileset'; max?: number; maxFileSize?: number };

type TableDefinition = {
  [columnName: string]: ColumnDefinition | '_keys';
} & {
  _keys?: {
    [keyName: string]: 'primary' | 'unique' | 'index';
  };
};

type SchemaDefinition = {
  [tableName: string]: TableDefinition;
};

/**
 * Define schema using object notation (alternative to builder API)
 */
export function defineSchema(definition: SchemaDefinition): Schema {
  const builder = new SchemaBuilder();
  
  for (const [tableName, tableDef] of Object.entries(definition)) {
    builder.table(tableName, t => {
      for (const [columnName, columnDef] of Object.entries(tableDef)) {
        if (columnName === '_keys') continue;
        
        const def = columnDef as ColumnDefinition;
        let column: any;
        
        switch (def.type) {
          case 'text':
            column = t.text(columnName);
            if (def.maxLength) column.maxLength(def.maxLength);
            break;
          case 'integer':
            column = t.integer(columnName);
            break;
          case 'real':
            column = t.real(columnName);
            break;
          case 'guid':
            column = t.guid(columnName);
            break;
          case 'date':
            column = t.date(columnName);
            break;
          case 'fileset':
            column = t.fileset(columnName);
            if (def.max) column.max(def.max);
            if (def.maxFileSize) column.maxFileSize(def.maxFileSize);
            break;
        }
        
        if (def.notNull && 'default' in def) {
          column.notNull(def.default);
        }
        
        if (def.lww) {
          column.lww();
        }
      }
      
      // Add keys
      const keys = (tableDef as any)._keys;
      if (keys) {
        for (const [keyName, keyType] of Object.entries(keys)) {
          const key = t.key(keyName);
          if (keyType === 'primary') key.primary();
          else if (keyType === 'unique') key.unique();
          else if (keyType === 'index') key.index();
        }
      }
    });
  }
  
  return builder.build();
}

// Usage
const schema = defineSchema({
  users: {
    id: { type: 'guid', notNull: true, default: '' },
    name: { type: 'text', notNull: true, default: '' },
    age: { type: 'integer', notNull: true, default: 0 },
    email: { type: 'text', notNull: true, default: '' },
    _keys: {
      id: 'primary',
      email: 'unique'
    }
  },
  posts: {
    id: { type: 'guid' },
    title: { type: 'text', maxLength: 200 },
    content: { type: 'text', lww: true },
    userId: { type: 'guid' },
    _keys: {
      id: 'primary',
      userId: 'index'
    }
  }
});
```

## Summary

This architecture provides:

1. **SQLite Adapter Layer**: Support for multiple backends (wa-sqlite, Capacitor, better-sqlite3)
2. **Type-Safe Schema Building**: Fluent and object-based APIs with full TypeScript support
3. **Zero-Codegen DbRecord**: Proxy-based typed access without build step
4. **RxJS Integration**: Industry-standard reactive streaming
5. **HLC Implementation**: Distributed timestamp system for conflict resolution
6. **Automatic Migration**: Schema diffing and migration generation

The design reduces complexity compared to Dart while maintaining all core features and adding TypeScript-specific improvements.

---

**Next Steps**: Begin implementation with Phase 1 (Foundation Setup) from the migration plan.
