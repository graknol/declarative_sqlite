import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { SqliteWasmAdapter } from '../database/sqlite-wasm-adapter';
import { SchemaBuilder } from '../schema/builders/schema-builder';
import { DeclarativeDatabase } from '../database/declarative-database';
import { QueryStreamManager } from './query-stream-manager';
import { StreamingQuery } from './streaming-query';

describe('Streaming Queries', () => {
  let adapter: SqliteWasmAdapter;
  let db: DeclarativeDatabase;
  
  beforeEach(async () => {
    adapter = new SqliteWasmAdapter();
    await adapter.open(':memory:');
    
    const schema = new SchemaBuilder()
      .table('users', t => {
        t.guid('id').notNull('');
        t.text('name').notNull('');
        t.integer('age').notNull(0);
        t.key('id').primary();
      })
      .build();
    
    db = new DeclarativeDatabase({ adapter, schema, autoMigrate: true });
    await db.initialize();
  });
  
  afterEach(async () => {
    await db.close();
    await adapter.close();
  });
  
  it('can create streaming query', async () => {
    const stream = new StreamingQuery(adapter, 'users');
    
    let emittedData: any[] | null = null;
    stream.subscribe(data => {
      emittedData = data;
    });
    
    // Wait for initial query
    await new Promise(resolve => setTimeout(resolve, 50));
    
    expect(emittedData).toEqual([]);
  });
  
  it('emits initial data', async () => {
    // Insert test data
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    await db.insert('users', { id: 'u2', name: 'Bob', age: 25 });
    
    const stream = new StreamingQuery(adapter, 'users');
    
    let emittedData: any[] | null = null;
    stream.subscribe(data => {
      emittedData = data;
    });
    
    // Wait for initial query
    await new Promise(resolve => setTimeout(resolve, 50));
    
    expect(emittedData).toHaveLength(2);
    expect(emittedData![0].name).toBe('Alice');
    expect(emittedData![1].name).toBe('Bob');
  });
  
  it('refreshes on manual refresh call', async () => {
    const stream = new StreamingQuery(adapter, 'users');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial query
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    
    // Insert data
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    
    // Manual refresh
    stream.refresh();
    
    // Wait for refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(1);
    expect(emissions[1][0].name).toBe('Alice');
  });
  
  it('stream manager notifies relevant streams', async () => {
    const streamManager = new QueryStreamManager();
    const usersStream = new StreamingQuery(adapter, 'users');
    const streamId = streamManager.registerStream(usersStream);
    
    const emissions: any[][] = [];
    usersStream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial query
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    
    // Insert data
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    
    // Notify stream manager
    streamManager.notifyTableChanged('users');
    
    // Wait for refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(1);
    
    streamManager.unregisterStream(streamId);
    streamManager.clear();
  });
  
  it('supports query options', async () => {
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    await db.insert('users', { id: 'u2', name: 'Bob', age: 25 });
    await db.insert('users', { id: 'u3', name: 'Charlie', age: 35 });
    
    const stream = new StreamingQuery(adapter, 'users', {
      where: 'age >= ?',
      whereArgs: [30],
      orderBy: 'name ASC'
    });
    
    let emittedData: any[] | null = null;
    stream.subscribe(data => {
      emittedData = data;
    });
    
    // Wait for initial query
    await new Promise(resolve => setTimeout(resolve, 50));
    
    expect(emittedData).toHaveLength(2);
    expect(emittedData![0].name).toBe('Alice');
    expect(emittedData![1].name).toBe('Charlie');
  });
  
  it('handles multiple concurrent streams', async () => {
    const streamManager = new QueryStreamManager();
    const stream1 = new StreamingQuery(adapter, 'users');
    const stream2 = new StreamingQuery(adapter, 'users', {
      where: 'age >= ?',
      whereArgs: [30]
    });
    
    const id1 = streamManager.registerStream(stream1);
    const id2 = streamManager.registerStream(stream2);
    
    const emissions1: any[][] = [];
    const emissions2: any[][] = [];
    
    stream1.subscribe(data => emissions1.push(data));
    stream2.subscribe(data => emissions2.push(data));
    
    // Wait for initial queries
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Insert data
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    await db.insert('users', { id: 'u2', name: 'Bob', age: 25 });
    
    // Notify all streams
    streamManager.notifyTableChanged('users');
    
    // Wait for refreshes
    await new Promise(resolve => setTimeout(resolve, 50));
    
    expect(emissions1).toHaveLength(2);
    expect(emissions1[1]).toHaveLength(2);
    
    expect(emissions2).toHaveLength(2);
    expect(emissions2[1]).toHaveLength(1); // Only Alice (age >= 30)
    
    streamManager.unregisterStream(id1);
    streamManager.unregisterStream(id2);
    streamManager.clear();
  });
  
  it('cleans up streams on unregister', () => {
    const streamManager = new QueryStreamManager();
    const stream = new StreamingQuery(adapter, 'users');
    const streamId = streamManager.registerStream(stream);
    
    expect(streamManager.getStreamCount()).toBe(1);
    
    streamManager.unregisterStream(streamId);
    
    expect(streamManager.getStreamCount()).toBe(0);
    streamManager.clear();
  });
  
  it('clears all streams', () => {
    const streamManager = new QueryStreamManager();
    const stream1 = new StreamingQuery(adapter, 'users');
    const stream2 = new StreamingQuery(adapter, 'users');
    
    streamManager.registerStream(stream1);
    streamManager.registerStream(stream2);
    
    expect(streamManager.getStreamCount()).toBe(2);
    
    streamManager.clear();
    
    expect(streamManager.getStreamCount()).toBe(0);
  });
});
