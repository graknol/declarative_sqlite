import { describe, it, expect, beforeEach } from 'vitest';
import { DeclarativeDatabase } from '../database/declarative-database';
import { BetterSqlite3Adapter } from '../database/better-sqlite3-adapter';
import { SchemaBuilder } from '../schema/builders/schema-builder';
import Database from 'better-sqlite3';

interface User {
  id: string;
  name: string;
  email: string;
  age: number;
}

describe('DbRecord', () => {
  let db: DeclarativeDatabase;
  let adapter: BetterSqlite3Adapter;

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

    adapter = new BetterSqlite3Adapter(Database);
    await adapter.open(':memory:');
    
    db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
    await db.initialize();
  });

  it('should create new record with Proxy', () => {
    const user = db.createRecord<User>('users');
    user.name = 'Alice';
    user.email = 'alice@example.com';
    user.age = 30;

    expect(user.name).toBe('Alice');
    expect(user.email).toBe('alice@example.com');
    expect(user.age).toBe(30);
  });

  it('should save new record', async () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-1';
    user.name = 'Bob';
    user.email = 'bob@example.com';
    user.age = 25;

    await user.save();

    const loaded = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-1'] });
    expect(loaded?.name).toBe('Bob');
    expect(loaded?.age).toBe(25);
  });

  it('should update existing record', async () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-2';
    user.name = 'Charlie';
    user.email = 'charlie@example.com';
    user.age = 35;
    await user.save();

    user.age = 36;
    await user.save();

    const loaded = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-2'] });
    expect(loaded?.age).toBe(36);
  });

  it('should delete record', async () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-3';
    user.name = 'Dave';
    user.email = 'dave@example.com';
    user.age = 40;
    await user.save();

    await user.delete();

    const loaded = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-3'] });
    expect(loaded).toBeNull();
  });

  it('should track dirty fields', () => {
    const user = db.createRecord<User>('users');
    expect(user.isDirty()).toBe(false);

    user.name = 'Eve';
    user.email = 'eve@example.com';

    expect(user.isDirty()).toBe(true);
    expect(user.getDirtyFields()).toContain('name');
    expect(user.getDirtyFields()).toContain('email');
  });

  it('should clear dirty fields after save', async () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-4';
    user.name = 'Frank';
    user.email = 'frank@example.com';
    user.age = 45;

    expect(user.isDirty()).toBe(true);

    await user.save();

    expect(user.isDirty()).toBe(false);
  });

  it('should access system columns', async () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-5';
    user.name = 'Grace';
    user.email = 'grace@example.com';
    user.age = 28;
    await user.save();

    expect((user as any).system_id).toBeDefined();
    expect((user as any).system_created_at).toBeDefined();
    expect((user as any).system_version).toBeDefined();
  });

  it('should load existing record', async () => {
    await db.insert('users', {
      id: 'user-6',
      name: 'Henry',
      email: 'henry@example.com',
      age: 50
    });

    const user = await db.loadRecord<User>('users', 'user-6');

    expect(user.name).toBe('Henry');
    expect(user.email).toBe('henry@example.com');
    expect(user.age).toBe(50);
  });

  it('should convert to JSON', () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-7';
    user.name = 'Ivy';
    user.email = 'ivy@example.com';
    user.age = 22;

    const json = user.toJSON();
    expect(json.id).toBe('user-7');
    expect(json.name).toBe('Ivy');
    expect(json.age).toBe(22);
  });

  it('should prevent setting system columns', () => {
    const user = db.createRecord<User>('users');
    
    expect(() => {
      (user as any).system_id = 'fake-id';
    }).toThrow();
  });
});
