# Plain Objects API - New Design

This document demonstrates the new plain objects API for declarative-sqlite, designed for simplicity and perfect Comlink compatibility.

## Overview

The new design eliminates the Proxy-based DbRecord system in favor of plain JavaScript objects. This makes records:
- ✅ Fully serializable through Comlink
- ✅ Compatible with structured clone
- ✅ JSON serializable
- ✅ Simpler to use and understand

## Basic Usage

### Creating and Saving Records

```typescript
import { SchemaBuilder, DeclarativeDatabase, AdapterFactory } from 'declarative-sqlite';

// Define schema
const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('');
    t.text('email').notNull('');
    t.integer('age').notNull(0);
    t.key('id').primary();
  })
  .build();

// Create database
const adapter = await AdapterFactory.create({ backend: 'memory' });
const db = new DeclarativeDatabase({ adapter, schema });
await db.initialize();

// Create a new record
const user = db.createRecord('users');
user.id = 'user-1';
user.name = 'Alice';
user.email = 'alice@example.com';
user.age = 30;

// Save (INSERT)
await db.save(user);

// Update
user.age = 31;
await db.save(user); // UPDATE - only changed fields

// Delete
await db.deleteRecord(user);
```

### Querying Records

```typescript
// Query returns plain objects
const users = await db.query('users', {
  where: 'age >= ?',
  whereArgs: [21],
  orderBy: 'name'
});

// Access data directly
console.log(users[0].name); // "Alice"

// Modify and save
users[0].age = 32;
await db.save(users[0]);
```

### Streaming Queries

```typescript
// Stream returns plain objects
const users$ = db.stream('users', {
  where: 'age >= ?',
  whereArgs: [21]
});

users$.subscribe(users => {
  console.log(`Found ${users.length} users`);
  users.forEach(user => {
    console.log(`${user.name} - ${user.age}`);
  });
});

// Any changes trigger refresh
await db.insert('users', { id: 'user-2', name: 'Bob', age: 25 });
// Stream subscribers automatically receive updated data
```

## Change Tracking with xRec

Each record has a hidden `xRec` property that stores the original database values:

```typescript
const user = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-1'] });

// xRec stores original values (non-enumerable)
const xRec = user.xRec;
console.log(xRec.name); // Original name from database

// Modify the record
user.name = 'Alice Smith';

// Compare with original
console.log(user.name !== user.xRec.name); // true - changed

// Save updates xRec to reflect new database state
await db.save(user);
console.log(user.name === user.xRec.name); // true - synced
```

## Comlink Integration

The new design works seamlessly with Comlink for web workers:

### Worker Setup (worker.ts)

```typescript
import { expose } from 'comlink';
import { DeclarativeDatabase, SchemaBuilder, AdapterFactory } from 'declarative-sqlite';

const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('');
    t.integer('age').notNull(0);
    t.key('id').primary();
  })
  .build();

const adapter = await AdapterFactory.create({ name: 'mydb.db' });
const db = new DeclarativeDatabase({ adapter, schema });
await db.initialize();

// Expose database methods
expose({
  query: (table: string, options?: any) => db.query(table, options),
  save: (record: any) => db.save(record),
  deleteRecord: (record: any) => db.deleteRecord(record),
  createRecord: (table: string) => db.createRecord(table),
});
```

### Main Thread (main.ts)

```typescript
import { wrap } from 'comlink';

const worker = new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' });
const db = wrap(worker);

// Query from worker - returns plain objects automatically
const users = await db.query('users');
console.log(users[0].name); // Works!

// Modify and save back through worker
users[0].age = 31;
await db.save(users[0]); // Serializes automatically!

// Create new record in worker
const newUser = await db.createRecord('users');
newUser.id = 'user-2';
newUser.name = 'Bob';
await db.save(newUser); // Works seamlessly!
```

## Migration from Old API

### Old DbRecord API (Deprecated)

```typescript
// ❌ Old way with Proxy objects
const user = db.createRecord('users');
user.name = 'Alice';
await user.save(); // Method on record

await user.delete(); // Method on record
```

### New Plain Objects API

```typescript
// ✅ New way with plain objects
const user = db.createRecord('users');
user.name = 'Alice';
await db.save(user); // Method on database

await db.deleteRecord(user); // Method on database
```

## Best Practices

### 1. Always use db.save() for modifications

```typescript
const user = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-1'] });
user.age = 31;
await db.save(user); // Automatically determines INSERT vs UPDATE
```

### 2. Use streaming queries for reactive UI

```typescript
const users$ = db.stream('users');
users$.subscribe(users => updateUI(users));
```

### 3. Leverage xRec for optimistic updates

```typescript
const user = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-1'] });
const originalName = user.xRec.name;

user.name = 'New Name';
try {
  await db.save(user);
} catch (error) {
  // Rollback to original
  user.name = originalName;
}
```

### 4. Records work across Comlink automatically

```typescript
// No special serialization needed!
const users = await workerDb.query('users');
users[0].age = 32;
await workerDb.save(users[0]); // Just works!
```

## Summary

The new plain objects API provides:

- ✅ **Simplicity**: No Proxy magic, just plain objects
- ✅ **Comlink Compatible**: Serializes automatically through workers
- ✅ **Change Tracking**: xRec property for detecting modifications
- ✅ **Type Safe**: Full TypeScript support
- ✅ **HLC Integration**: Automatic timestamp management
- ✅ **Streaming Support**: RxJS observables for reactive updates

Perfect for offline-first PWAs with web worker databases!
