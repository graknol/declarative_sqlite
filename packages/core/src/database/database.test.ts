import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { DeclarativeDatabase } from './declarative-database';
import { SchemaBuilder } from '../schema/builders/schema-builder';
import { SqliteWasmAdapter } from './sqlite-wasm-adapter';

describe('DeclarativeDatabase', () => {
  let db: DeclarativeDatabase;
  let adapter: SqliteWasmAdapter;

  beforeEach(async () => {
    // Create sqlite-wasm adapter
    adapter = new SqliteWasmAdapter();
    await adapter.open(':memory:');

    // Create simple schema
    const schema = new SchemaBuilder()
      .table('users', t => {
        t.guid('id').notNull('');
        t.text('name').notNull('');
        t.integer('age').notNull(0);
        t.key('id').primary();
      })
      .build();

    // Create database with auto-migrate enabled
    db = new DeclarativeDatabase({
      adapter,
      schema,
      autoMigrate: true,
    });

    await db.initialize();
  });

  afterEach(async () => {
    await db.close();
  });

  it('should insert a record', async () => {
    await db.insert('users', {
      id: '123',
      name: 'Alice',
      age: 30,
    });

    // For tables without INTEGER PRIMARY KEY, verify the insert by querying
    const users = await db.query('users');
    expect(users.length).toBe(1);
    expect(users[0].name).toBe('Alice');
  });

  it('should insert multiple records', async () => {
    await db.insertMany('users', [
      { id: '1', name: 'Alice', age: 30 },
      { id: '2', name: 'Bob', age: 25 },
    ]);

    const users = await db.query('users');
    expect(users.length).toBe(2);
  });

  it('should update records', async () => {
    await db.insert('users', { id: '123', name: 'Alice', age: 30 });

    const changes = await db.update(
      'users',
      { age: 31 },
      { where: 'id = ?', whereArgs: ['123'] }
    );

    expect(changes).toBe(1);
  });

  it('should delete records', async () => {
    await db.insert('users', { id: '123', name: 'Alice', age: 30 });

    const changes = await db.delete('users', {
      where: 'id = ?',
      whereArgs: ['123'],
    });

    expect(changes).toBe(1);
  });

  it('should query records', async () => {
    await db.insert('users', { id: '123', name: 'Alice', age: 30 });

    const users = await db.query('users', {
      where: 'age > ?',
      whereArgs: [25],
    });

    expect(Array.isArray(users)).toBe(true);
    expect(users.length).toBe(1);
  });

  it('should query a single record', async () => {
    await db.insert('users', { id: '123', name: 'Alice', age: 30 });

    const user = await db.queryOne('users', {
      where: 'id = ?',
      whereArgs: ['123'],
    });

    expect(user).toBeTruthy();
    expect(user?.name).toBe('Alice');
  });

  it('should execute transactions', async () => {
    await db.transaction(async () => {
      await db.insert('users', { id: '1', name: 'Alice', age: 30 });
      await db.insert('users', { id: '2', name: 'Bob', age: 25 });
    });

    const users = await db.query('users');
    expect(users.length).toBe(2);
  });

  it('should throw if not initialized', async () => {
    const uninitDb = new DeclarativeDatabase({
      adapter,
      schema: new SchemaBuilder().build(),
      autoMigrate: false,
    });

    await expect(uninitDb.insert('users', { name: 'Alice' })).rejects.toThrow();
  });
});
