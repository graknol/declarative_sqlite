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

describe('DbRecord', () => {
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

    await db.save(user);

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
    await db.save(user);

    user.age = 36;
    await db.save(user);

    const loaded = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-2'] });
    expect(loaded?.age).toBe(36);
  });

  it('should delete record', async () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-3';
    user.name = 'Dave';
    user.email = 'dave@example.com';
    user.age = 40;
    await db.save(user);

    await db.deleteRecord(user);

    const loaded = await db.queryOne('users', { where: 'id = ?', whereArgs: ['user-3'] });
    expect(loaded).toBeNull();
  });

  it('should track dirty fields', () => {
    const user = db.createRecord<User>('users');
    const xRec = (user as any).xRec || {};
    
    // Initially no changes
    expect(user.name).toBe(xRec.name);

    user.name = 'Eve';
    user.email = 'eve@example.com';

    // Now there are changes
    expect(user.name).not.toBe(xRec.name);
    expect(user.email).not.toBe(xRec.email);
  });

  it('should clear dirty fields after save', async () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-4';
    user.name = 'Frank';
    user.email = 'frank@example.com';
    user.age = 45;

    const xRecBefore = (user as any).xRec || {};
    expect(user.name).not.toBe(xRecBefore.name);

    await db.save(user);

    // After save, xRec is updated with fresh data from the database
    const xRecAfter = (user as any).xRec || {};
    expect(user.name).toBe(xRecAfter.name);
  });

  it('should access system columns', async () => {
    const user = db.createRecord<User>('users');
    user.id = 'user-5';
    user.name = 'Grace';
    user.email = 'grace@example.com';
    user.age = 28;
    await db.save(user);

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

    // Plain objects can be directly serialized with JSON.stringify
    const json = JSON.parse(JSON.stringify(user));
    expect(json.id).toBe('user-7');
    expect(json.name).toBe('Ivy');
    expect(json.age).toBe(22);
    // Note: xRec and __tableName are non-enumerable so they don't appear in JSON
  });

  it('should allow setting system columns', () => {
    const user = db.createRecord<User>('users');
    
    (user as any).system_id = 'fake-id';
    expect((user as any).system_id).toBe('fake-id');
  });
});
