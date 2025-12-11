# Comlink Integration Guide

This guide explains how to use `declarative-sqlite` with [Comlink](https://github.com/GoogleChromeLabs/comlink) to enable DbRecord serialization across web worker boundaries.

## Overview

When using `declarative-sqlite` in a web worker with Comlink, `DbRecord` instances cannot be directly transferred between the worker and the main thread because they contain:

- Proxy objects
- Methods
- Private properties
- References to the database instance

This library provides built-in serialization support to solve this problem.

## Solution Approaches

There are two approaches to handle DbRecord serialization with Comlink:

### 1. Manual Serialization (Recommended)

The simplest approach is to manually serialize DbRecord instances before returning them from worker functions.

**Worker code:**

```typescript
import { expose } from 'comlink';
import { DeclarativeDatabase, serializeDbRecords } from 'declarative-sqlite';

const db = new DeclarativeDatabase({ /* config */ });
await db.initialize();

const api = {
  async getUsers() {
    const users = await db.query('users');
    // Manually serialize before returning
    return serializeDbRecords(users);
  },

  async getUserById(id: string) {
    const user = await db.queryOne('users', { where: 'id = ?', whereArgs: [id] });
    if (!user) return null;
    // Manually serialize single record
    return serializeDbRecord(user);
  },
};

expose(api);
```

**Main thread code:**

```typescript
import { wrap } from 'comlink';
import { deserializeDbRecords, deserializeDbRecord } from 'declarative-sqlite';

const worker = new Worker('./db-worker.js');
const api = wrap(worker);

// Query users
const serializedUsers = await api.getUsers();
const users = deserializeDbRecords(serializedUsers);

console.log(users[0].name); // Access properties
console.log(users[0].toJSON()); // Get plain object

// Query single user
const serializedUser = await api.getUserById('user-1');
if (serializedUser) {
  const user = deserializeDbRecord(serializedUser);
  console.log(user.name);
}
```

### 2. Automatic Transfer Handler (Advanced)

For automatic serialization, you can register a Comlink transfer handler:

**Worker code:**

```typescript
import { expose, transferHandlers } from 'comlink';
import { DeclarativeDatabase, registerDbRecordTransferHandler } from 'declarative-sqlite';

// Register the transfer handler
registerDbRecordTransferHandler(transferHandlers);

const db = new DeclarativeDatabase({ /* config */ });
await db.initialize();

const api = {
  async getUsers() {
    // DbRecords will be automatically serialized
    return await db.query('users');
  },

  async getUserById(id: string) {
    return await db.queryOne('users', { where: 'id = ?', whereArgs: [id] });
  },
};

expose(api);
```

**Main thread code:**

```typescript
import { wrap, transferHandlers } from 'comlink';
import { registerDbRecordTransferHandler } from 'declarative-sqlite';

// Register the transfer handler in main thread too
registerDbRecordTransferHandler(transferHandlers);

const worker = new Worker('./db-worker.js');
const api = wrap(worker);

// DbRecords are automatically deserialized
const users = await api.getUsers();
console.log(users[0].name); // Works!

const user = await api.getUserById('user-1');
if (user) {
  console.log(user.name);
}
```

## Read-Only Records

When DbRecords are deserialized on the main thread, they become **read-only** records. This is because they don't have access to the database connection.

**What works:**

```typescript
// ✅ Reading properties
console.log(user.name);
console.log(user.email);

// ✅ Converting to JSON
const json = user.toJSON();

// ✅ Checking dirty state
const isDirty = user.isDirty();
const dirtyFields = user.getDirtyFields();
```

**What doesn't work:**

```typescript
// ❌ Saving (throws error)
await user.save();
// Error: Cannot call save() on a read-only DbRecord

// ❌ Deleting (throws error)
await user.delete();
// Error: Cannot call delete() on a read-only DbRecord

// ❌ Setting properties (properties exist but can't be saved)
user.name = 'New Name'; // This sets the value locally but has no effect on the database
```

## Best Practices

### 1. Use Plain Data for Modifications

Instead of modifying serialized records, use the database API directly:

```typescript
// Worker API
const api = {
  async updateUser(id: string, updates: Record<string, any>) {
    await db.update('users', updates, { 
      where: 'id = ?', 
      whereArgs: [id] 
    });
  },

  async deleteUser(id: string) {
    await db.delete('users', {
      where: 'id = ?',
      whereArgs: [id]
    });
  },
};
```

### 2. Return Plain Objects for Forms

For forms and editable UI, return plain objects instead of DbRecords:

```typescript
// Worker API
const api = {
  async getUserData(id: string) {
    const user = await db.queryOne('users', { 
      where: 'id = ?', 
      whereArgs: [id] 
    });
    // Return plain object
    return user ? user.toJSON() : null;
  },
};
```

### 3. Separate Query and Mutation APIs

Design your worker API to separate data fetching from mutations:

```typescript
const api = {
  // Query APIs (return serialized or plain data)
  queries: {
    async getUsers() {
      const users = await db.query('users');
      return serializeDbRecords(users);
    },
  },

  // Mutation APIs (accept plain data)
  mutations: {
    async createUser(userData: Record<string, any>) {
      return await db.insert('users', userData);
    },

    async updateUser(id: string, updates: Record<string, any>) {
      await db.update('users', updates, {
        where: 'id = ?',
        whereArgs: [id]
      });
    },
  },
};
```

## API Reference

### Serialization Functions

#### `serializeDbRecord<T>(record: DbRecord<T> & T): SerializableDbRecord`

Serialize a single DbRecord to a plain object.

#### `serializeDbRecords<T>(records: (DbRecord<T> & T)[]): SerializableDbRecord[]`

Serialize an array of DbRecords.

#### `deserializeDbRecord(data: SerializableDbRecord): ReadonlyDbRecord`

Deserialize a plain object to a read-only DbRecord-like object.

#### `deserializeDbRecords(data: SerializableDbRecord[]): ReadonlyDbRecord[]`

Deserialize an array of serialized records.

### Type Guards

#### `isDbRecord(value: any): value is DbRecord<any>`

Check if a value is a DbRecord instance.

#### `isSerializableDbRecord(value: any): value is SerializableDbRecord`

Check if a value is a serialized DbRecord.

### Transfer Handler

#### `registerDbRecordTransferHandler(transferHandlers: Map<string, any>): void`

Register Comlink transfer handler for automatic DbRecord serialization.

## TypeScript Types

```typescript
interface SerializableDbRecord {
  __type: 'SerializableDbRecord';
  tableName: string;
  values: Record<string, any>;
  isNew: boolean;
  dirtyFields: string[];
}

interface ReadonlyDbRecord {
  [key: string]: any;
  toJSON: () => Record<string, any>;
  isDirty: () => boolean;
  getDirtyFields: () => string[];
  save: () => Promise<void>; // Throws error
  delete: () => Promise<void>; // Throws error
  __readonly: true;
  __tableName: string;
  __isNew: boolean;
}
```

## Example: Complete Worker Setup

Here's a complete example of a worker-based database setup:

**db-worker.ts:**

```typescript
import { expose } from 'comlink';
import { 
  DeclarativeDatabase, 
  SchemaBuilder, 
  AdapterFactory,
  serializeDbRecords,
  serializeDbRecord,
} from 'declarative-sqlite';

const schema = new SchemaBuilder()
  .table('users', t => {
    t.guid('id').notNull('');
    t.text('name').notNull('');
    t.text('email').notNull('');
    t.integer('age').notNull(0);
    t.key('id').primary();
  })
  .build();

const adapter = await AdapterFactory.create({
  name: 'myapp.db',
  backend: 'opfs',
});

const db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
await db.initialize();

const api = {
  // Queries
  async getUsers() {
    const users = await db.query('users');
    return serializeDbRecords(users);
  },

  async getUserById(id: string) {
    const user = await db.queryOne('users', { where: 'id = ?', whereArgs: [id] });
    return user ? serializeDbRecord(user) : null;
  },

  // Mutations
  async createUser(userData: { id: string; name: string; email: string; age: number }) {
    return await db.insert('users', userData);
  },

  async updateUser(id: string, updates: Partial<{ name: string; email: string; age: number }>) {
    await db.update('users', updates, { where: 'id = ?', whereArgs: [id] });
  },

  async deleteUser(id: string) {
    await db.delete('users', { where: 'id = ?', whereArgs: [id] });
  },
};

expose(api);
```

**main.ts:**

```typescript
import { wrap } from 'comlink';
import { deserializeDbRecords, deserializeDbRecord } from 'declarative-sqlite';

const worker = new Worker(new URL('./db-worker.ts', import.meta.url), { type: 'module' });
const api = wrap<typeof import('./db-worker').api>(worker);

// Create user
await api.createUser({
  id: 'user-1',
  name: 'Alice',
  email: 'alice@example.com',
  age: 30,
});

// Query users
const serializedUsers = await api.getUsers();
const users = deserializeDbRecords(serializedUsers);

console.log('Users:', users.map(u => u.name));

// Update user
await api.updateUser('user-1', { age: 31 });

// Query single user
const serializedUser = await api.getUserById('user-1');
if (serializedUser) {
  const user = deserializeDbRecord(serializedUser);
  console.log('Updated user:', user.toJSON());
}

// Delete user
await api.deleteUser('user-1');
```

## Troubleshooting

### "Unserializable return value" Error

This error occurs when trying to return DbRecord instances directly without serialization:

```typescript
// ❌ Wrong - DbRecord can't be serialized by Comlink
async getUsers() {
  return await db.query('users');
}

// ✅ Correct - Manually serialize
async getUsers() {
  const users = await db.query('users');
  return serializeDbRecords(users);
}
```

### "Cannot call save() on a read-only DbRecord" Error

This occurs when trying to modify records in the main thread:

```typescript
// ❌ Wrong - Can't save in main thread
const user = deserializeDbRecord(serializedUser);
user.name = 'New Name';
await user.save(); // Error!

// ✅ Correct - Use worker API
await api.updateUser(user.id, { name: 'New Name' });
```

## Performance Considerations

1. **Serialization overhead**: Serialization adds a small overhead. For large result sets, consider pagination.
2. **Memory usage**: Serialized data is duplicated during transfer. Use streaming for very large datasets.
3. **Network-like latency**: Worker communication has latency similar to network requests. Batch operations when possible.

## Conclusion

With proper serialization, `declarative-sqlite` works seamlessly with Comlink and web workers. The key is to:

1. Serialize DbRecords before returning from worker functions
2. Deserialize on the main thread to get read-only access
3. Use worker APIs for all database modifications
4. Consider returning plain objects (via `toJSON()`) for editable data

This architecture keeps the database logic in the worker while providing type-safe, reactive data access in the main thread.
