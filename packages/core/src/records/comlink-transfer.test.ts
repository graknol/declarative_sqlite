import { describe, it, expect, beforeEach } from 'vitest';
import { DeclarativeDatabase } from '../database/declarative-database';
import { SqliteWasmAdapter } from '../database/sqlite-wasm-adapter';
import { SchemaBuilder } from '../schema/builders/schema-builder';

interface User {
  id: string;
  name: string;
  email: string;
  age: number;
}

describe('Plain Object Comlink Compatibility', () => {
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

  describe('Plain objects are serializable', () => {
    it('should serialize a new record through JSON', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Alice';
      user.email = 'alice@example.com';
      user.age = 30;

      // Plain objects can be serialized directly with JSON
      const json = JSON.stringify(user);
      const deserialized = JSON.parse(json);

      expect(deserialized.id).toBe('user-1');
      expect(deserialized.name).toBe('Alice');
      expect(deserialized.email).toBe('alice@example.com');
      expect(deserialized.age).toBe(30);
      // xRec and __tableName are non-enumerable and don't appear in JSON
    });

    it('should serialize an existing record through JSON', async () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Bob';
      user.email = 'bob@example.com';
      user.age = 25;
      await db.save(user);

      const json = JSON.stringify(user);
      const deserialized = JSON.parse(json);

      expect(deserialized).toHaveProperty('system_id');
      expect(deserialized.name).toBe('Bob');
    });

    it('should preserve data through structured clone', () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Dave';
      user.email = 'dave@example.com';
      user.age = 40;

      // Structured clone is what Comlink uses
      const cloned = structuredClone(user);

      expect(cloned.name).toBe('Dave');
      expect(cloned.email).toBe('dave@example.com');
      expect(cloned.age).toBe(40);
    });

    it('should handle xRec property correctly', async () => {
      await db.insert('users', {
        id: 'user-1',
        name: 'Alice',
        email: 'alice@example.com',
        age: 30
      });

      const user = await db.queryOne<User>('users', { where: 'id = ?', whereArgs: ['user-1'] });
      expect(user).not.toBeNull();
      
      if (user) {
        // xRec exists but is non-enumerable
        const xRec = (user as any).xRec;
        expect(xRec).toBeDefined();
        expect(xRec.name).toBe('Alice');
        
        // When serialized, xRec doesn't appear
        const json = JSON.stringify(user);
        const parsed = JSON.parse(json);
        expect(parsed.xRec).toBeUndefined();
      }
    });
  });

  describe('Query results are plain objects', () => {
    it('should return plain objects from query', async () => {
      await db.insert('users', { id: 'user-1', name: 'Alice', email: 'alice@example.com', age: 30 });
      await db.insert('users', { id: 'user-2', name: 'Bob', email: 'bob@example.com', age: 25 });

      const users = await db.query<User>('users');

      expect(users).toHaveLength(2);
      expect(users[0].name).toBe('Alice');
      expect(users[1].name).toBe('Bob');
      
      // Can be serialized directly
      const json = JSON.stringify(users);
      const parsed = JSON.parse(json);
      expect(parsed[0].name).toBe('Alice');
      expect(parsed[1].name).toBe('Bob');
    });

    it('should work with queryOne results', async () => {
      await db.insert('users', { id: 'user-1', name: 'Charlie', email: 'charlie@example.com', age: 35 });

      const user = await db.queryOne<User>('users', { where: 'id = ?', whereArgs: ['user-1'] });
      
      expect(user).not.toBeNull();
      if (!user) return;

      expect(user.name).toBe('Charlie');
      expect(user.email).toBe('charlie@example.com');
      
      // Can be serialized directly
      const json = JSON.stringify(user);
      const parsed = JSON.parse(json);
      expect(parsed.name).toBe('Charlie');
    });

    it('should handle arrays through structuredClone', async () => {
      await db.insert('users', { id: 'user-1', name: 'Dave', email: 'dave@example.com', age: 40 });
      await db.insert('users', { id: 'user-2', name: 'Eve', email: 'eve@example.com', age: 35 });

      const users = await db.query<User>('users');

      // structuredClone is what Comlink uses internally
      const cloned = structuredClone(users);

      expect(cloned).toHaveLength(2);
      expect(cloned[0].name).toBe('Dave');
      expect(cloned[1].name).toBe('Eve');
    });
  });

  describe('Save and delete with plain objects', () => {
    it('should save new records', async () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-1';
      user.name = 'Frank';
      user.email = 'frank@example.com';
      user.age = 45;

      await db.save(user);

      const loaded = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-1'] });
      expect(loaded?.name).toBe('Frank');
    });

    it('should update existing records', async () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-2';
      user.name = 'Grace';
      user.email = 'grace@example.com';
      user.age = 50;
      await db.save(user);

      user.age = 51;
      await db.save(user);

      const loaded = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-2'] });
      expect(loaded?.age).toBe(51);
    });

    it('should delete records', async () => {
      const user = db.createRecord<User>('users');
      user.id = 'user-3';
      user.name = 'Helen';
      user.email = 'helen@example.com';
      user.age = 55;
      await db.save(user);

      await db.deleteRecord(user);

      const loaded = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-3'] });
      expect(loaded).toBeNull();
    });
  });
});
