import { describe, it, expect, beforeEach } from 'vitest';
import { DeclarativeDatabase } from '../database/declarative-database';
import { SqliteWasmAdapter } from '../database/sqlite-wasm-adapter';
import { SchemaBuilder } from '../schema/builders/schema-builder';
import { 
  serializeDbRecord, 
  deserializeDbRecord,
  serializeDbRecords,
  deserializeDbRecords,
  isDbRecord,
  isSerializableDbRecord,
} from './comlink-transfer';
import { DbRecord } from './db-record';

interface User {
  id: string;
  name: string;
  email: string;
  age: number;
}

describe('DbRecord Comlink Serialization', () => {
  let db: DeclarativeDatabase;
  let adapter: SqliteWasmAdapter;

  beforeEach(async () => {
    const schema = new SchemaBuilder()
      .table('users', t => {
        t.guid('id').notNull('');
        t.text('name').notNull('');
        t.text('email').notNull('');
        t.integer('age').notNull(0);
        t.key('id').primary();
      })
      .build();

    adapter = new SqliteWasmAdapter();
    await adapter.open(':memory:');
    
    db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
    await db.initialize();
  });

  describe('toSerializable and fromSerializable', () => {
    it('should serialize a new DbRecord', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Alice';
      user.email = 'alice@example.com';
      user.age = 30;

      const serialized = (user as any).toSerializable();

      expect(serialized).toHaveProperty('__type', 'SerializableDbRecord');
      expect(serialized.tableName).toBe('users');
      expect(serialized.values.name).toBe('Alice');
      expect(serialized.values.email).toBe('alice@example.com');
      expect(serialized.values.age).toBe(30);
      expect(serialized.isNew).toBe(true);
    });

    it('should serialize an existing DbRecord', async () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Bob';
      user.email = 'bob@example.com';
      user.age = 25;
      await user.save();

      const serialized = (user as any).toSerializable();

      expect(serialized.isNew).toBe(false);
      expect(serialized.values).toHaveProperty('system_id');
      expect(serialized.values.name).toBe('Bob');
    });

    it('should deserialize to a read-only record', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Charlie';
      user.email = 'charlie@example.com';
      user.age = 35;

      const serialized = (user as any).toSerializable();
      const readonly = DbRecord.fromSerializable(serialized);

      expect(readonly.name).toBe('Charlie');
      expect(readonly.email).toBe('charlie@example.com');
      expect(readonly.age).toBe(35);
      expect(readonly.__readonly).toBe(true);
      expect(readonly.__tableName).toBe('users');
    });

    it('should preserve data through serialize/deserialize cycle', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Dave';
      user.email = 'dave@example.com';
      user.age = 40;
      user.name = 'David'; // Mark as dirty

      const serialized = (user as any).toSerializable();
      const readonly = DbRecord.fromSerializable(serialized);

      expect(readonly.name).toBe('David');
      expect(readonly.email).toBe('dave@example.com');
      expect(readonly.age).toBe(40);
      expect(readonly.isDirty()).toBe(true);
      expect(readonly.getDirtyFields()).toContain('name');
    });

    it('should throw error when calling save() on read-only record', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Eve';

      const serialized = (user as any).toSerializable();
      const readonly = DbRecord.fromSerializable(serialized);

      expect(readonly.save()).rejects.toThrow('Cannot call save() on a read-only DbRecord');
    });

    it('should throw error when calling delete() on read-only record', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Frank';

      const serialized = (user as any).toSerializable();
      const readonly = DbRecord.fromSerializable(serialized);

      expect(readonly.delete()).rejects.toThrow('Cannot call delete() on a read-only DbRecord');
    });

    it('should reject invalid serialized data', () => {
      const invalidData = { __type: 'InvalidType', values: {} };
      
      expect(() => DbRecord.fromSerializable(invalidData as any)).toThrow('Invalid serialized DbRecord data');
    });
  });

  describe('Helper functions', () => {
    it('serializeDbRecord should work', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'George';
      user.email = 'george@example.com';
      user.age = 45;

      const serialized = serializeDbRecord(user);

      expect(serialized.__type).toBe('SerializableDbRecord');
      expect(serialized.values.name).toBe('George');
    });

    it('deserializeDbRecord should work', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Helen';

      const serialized = serializeDbRecord(user);
      const readonly = deserializeDbRecord(serialized);

      expect(readonly.name).toBe('Helen');
      expect(readonly.__readonly).toBe(true);
    });

    it('serializeDbRecords should handle arrays', async () => {
      const users = [
        db.createRecord<User>('users'),
        db.createRecord<User>('users'),
        db.createRecord<User>('users'),
      ];

      users[0].id = 'user-1';
      users[0].name = 'Alice';
      users[1].id = 'user-2';
      users[1].name = 'Bob';
      users[2].id = 'user-3';
      users[2].name = 'Charlie';

      const serialized = serializeDbRecords(users);

      expect(serialized).toHaveLength(3);
      expect(serialized[0].values.name).toBe('Alice');
      expect(serialized[1].values.name).toBe('Bob');
      expect(serialized[2].values.name).toBe('Charlie');
    });

    it('deserializeDbRecords should handle arrays', () => {
      const users = [
        db.createRecord<User>('users'),
        db.createRecord<User>('users'),
      ];

      users[0].id = 'user-1';
      users[0].name = 'Dave';
      users[1].id = 'user-2';
      users[1].name = 'Eve';

      const serialized = serializeDbRecords(users);
      const readonly = deserializeDbRecords(serialized);

      expect(readonly).toHaveLength(2);
      expect(readonly[0].name).toBe('Dave');
      expect(readonly[1].name).toBe('Eve');
      expect(readonly[0].__readonly).toBe(true);
      expect(readonly[1].__readonly).toBe(true);
    });

    it('isDbRecord should identify DbRecord instances', () => {
      const user = db.createRecord<User>('users');
      const plainObject = { name: 'Test' };
      const serialized = serializeDbRecord(user);

      expect(isDbRecord(user)).toBe(true);
      expect(isDbRecord(plainObject)).toBe(false);
      expect(isDbRecord(serialized)).toBe(false);
      expect(isDbRecord(null)).toBe(false);
      expect(isDbRecord(undefined)).toBe(false);
    });

    it('isSerializableDbRecord should identify serialized records', () => {
      const user = db.createRecord<User>('users');
      const serialized = serializeDbRecord(user);
      const plainObject = { name: 'Test' };

      expect(isSerializableDbRecord(serialized)).toBe(true);
      expect(isSerializableDbRecord(user)).toBe(false);
      expect(isSerializableDbRecord(plainObject)).toBe(false);
      expect(isSerializableDbRecord(null)).toBe(false);
      expect(isSerializableDbRecord(undefined)).toBe(false);
    });
  });

  describe('Integration with query methods', () => {
    it('should serialize query results', async () => {
      // Insert some test data
      await db.insert('users', { id: 'user-1', name: 'Alice', email: 'alice@example.com', age: 30 });
      await db.insert('users', { id: 'user-2', name: 'Bob', email: 'bob@example.com', age: 25 });

      // Query records
      const users = await db.query<User>('users');

      // Serialize the results
      const serialized = serializeDbRecords(users);

      expect(serialized).toHaveLength(2);
      expect(serialized[0].values.name).toBe('Alice');
      expect(serialized[1].values.name).toBe('Bob');

      // Deserialize and verify
      const readonly = deserializeDbRecords(serialized);
      expect(readonly[0].name).toBe('Alice');
      expect(readonly[1].name).toBe('Bob');
    });

    it('should work with queryOne results', async () => {
      await db.insert('users', { id: 'user-1', name: 'Charlie', email: 'charlie@example.com', age: 35 });

      const user = await db.queryOne<User>('users', { where: 'id = ?', whereArgs: ['user-1'] });
      
      expect(user).not.toBeNull();
      if (!user) return;

      const serialized = serializeDbRecord(user);
      const readonly = deserializeDbRecord(serialized);

      expect(readonly.name).toBe('Charlie');
      expect(readonly.email).toBe('charlie@example.com');
    });
  });

  describe('toJSON compatibility', () => {
    it('toJSON should work on serialized records', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Ian';
      user.email = 'ian@example.com';
      user.age = 50;

      const serialized = serializeDbRecord(user);
      const readonly = deserializeDbRecord(serialized);

      const json = readonly.toJSON();

      expect(json.name).toBe('Ian');
      expect(json.email).toBe('ian@example.com');
      expect(json.age).toBe(50);
    });

    it('JSON.stringify should work on serialized records', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Jane';
      user.age = 28;

      const serialized = serializeDbRecord(user);
      const readonly = deserializeDbRecord(serialized);

      const jsonString = JSON.stringify(readonly.toJSON());
      const parsed = JSON.parse(jsonString);

      expect(parsed.name).toBe('Jane');
      expect(parsed.age).toBe(28);
    });
  });
});
