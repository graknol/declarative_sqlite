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
    const stream = new StreamingQuery(db, 'users');
    
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
    
    const stream = new StreamingQuery(db, 'users');
    
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
    const stream = new StreamingQuery(db, 'users');
    
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
    const usersStream = new StreamingQuery(db, 'users');
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
    
    const stream = new StreamingQuery(db, 'users', {
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
    const stream1 = new StreamingQuery(db, 'users');
    const stream2 = new StreamingQuery(db, 'users', {
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
    const stream = new StreamingQuery(db, 'users');
    const streamId = streamManager.registerStream(stream);
    
    expect(streamManager.getStreamCount()).toBe(1);
    
    streamManager.unregisterStream(streamId);
    
    expect(streamManager.getStreamCount()).toBe(0);
    streamManager.clear();
  });
  
  it('clears all streams', () => {
    const streamManager = new QueryStreamManager();
    const stream1 = new StreamingQuery(db, 'users');
    const stream2 = new StreamingQuery(db, 'users');
    
    streamManager.registerStream(stream1);
    streamManager.registerStream(stream2);
    
    expect(streamManager.getStreamCount()).toBe(2);
    
    streamManager.clear();
    
    expect(streamManager.getStreamCount()).toBe(0);
  });

  it('emits initial data immediately on subscription', async () => {
    // Insert test data first
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    await db.insert('users', { id: 'u2', name: 'Bob', age: 25 });
    
    const stream = new StreamingQuery(db, 'users');
    
    // Use a promise to track emissions
    const firstEmission = new Promise<any[]>((resolve) => {
      stream.subscribe(data => {
        resolve(data);
      });
    });
    
    const result = await firstEmission;
    
    expect(result).toHaveLength(2);
    expect(result[0].name).toBe('Alice');
    expect(result[1].name).toBe('Bob');
  });

  it('emits initial data synchronously if possible', async () => {
    // Insert test data
    await db.insert('users', { id: 'u1', name: 'Test User', age: 25 });
    
    const stream = new StreamingQuery(db, 'users');
    
    const emissions: any[][] = [];
    
    // Subscribe and track all emissions
    const subscription = stream.subscribe({
      next: (data) => {
        emissions.push(data);
      }
    });
    
    // Wait a bit for async query to complete
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Should have received at least one emission with the initial data
    expect(emissions.length).toBeGreaterThanOrEqual(1);
    expect(emissions[0]).toHaveLength(1);
    expect(emissions[0][0].name).toBe('Test User');
    
    subscription.unsubscribe();
  });

  it('handles empty table on initial emission', async () => {
    const stream = new StreamingQuery(db, 'users');
    
    const firstEmission = new Promise<any[]>((resolve) => {
      stream.subscribe(data => {
        resolve(data);
      });
    });
    
    const result = await firstEmission;
    
    expect(result).toEqual([]);
  });

  it('updates stream when data changes', async () => {
    const stream = new StreamingQuery(db, 'users');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial empty emission
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    expect(emissions[0]).toEqual([]);
    
    // Add data and refresh
    await db.insert('users', { id: 'u1', name: 'New User', age: 28 });
    stream.refresh();
    
    await new Promise(resolve => setTimeout(resolve, 50));
    
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(1);
    expect(emissions[1][0].name).toBe('New User');
  });

  it('preserves xRec and __tableName in streamed results', async () => {
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    
    const stream = new StreamingQuery(db, 'users');
    
    const firstEmission = new Promise<any[]>((resolve) => {
      stream.subscribe(data => {
        resolve(data);
      });
    });
    
    const result = await firstEmission;
    
    expect(result).toHaveLength(1);
    const user = result[0];
    
    // Check that tracking properties exist
    expect(user.xRec).toBeDefined();
    expect(user.__tableName).toBe('users');
    
    // Check that xRec has the original data
    expect(user.xRec.name).toBe('Alice');
    expect(user.xRec.age).toBe(30);
  });

  it('automatically pushes updates when data changes via db.stream()', async () => {
    // Use db.stream() which auto-registers with stream manager
    const stream = db.stream('users');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial empty emission
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    expect(emissions[0]).toEqual([]);
    
    // Insert data through db - should auto-notify stream
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    
    // Wait for automatic refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Should have automatically received update
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(1);
    expect(emissions[1][0].name).toBe('Alice');
  });

  it('automatically pushes updates on update operations', async () => {
    // Insert initial data
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    
    // Create stream
    const stream = db.stream('users');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial emission
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    expect(emissions[0][0].name).toBe('Alice');
    
    // Update data - should auto-notify stream
    await db.update('users', { age: 31 }, {
      where: 'id = ?',
      whereArgs: ['u1']
    });
    
    // Wait for automatic refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Should have automatically received update
    expect(emissions).toHaveLength(2);
    expect(emissions[1][0].age).toBe(31);
  });

  it('automatically pushes updates on delete operations', async () => {
    // Insert initial data
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    await db.insert('users', { id: 'u2', name: 'Bob', age: 25 });
    
    // Create stream
    const stream = db.stream('users');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial emission
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    expect(emissions[0]).toHaveLength(2);
    
    // Delete data - should auto-notify stream
    await db.delete('users', {
      where: 'id = ?',
      whereArgs: ['u1']
    });
    
    // Wait for automatic refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Should have automatically received update
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(1);
    expect(emissions[1][0].name).toBe('Bob');
  });

  it('automatically pushes updates on bulkLoad operations', async () => {
    // Create stream first
    const stream = db.stream('users');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial empty emission
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    expect(emissions[0]).toEqual([]);
    
    // Bulk load data - should auto-notify stream
    await db.bulkLoad('users', [
      { system_id: 'u1', id: 'u1', name: 'Alice', age: 30, system_version: '1-0', system_created_at: '1-0', system_is_local_origin: 0 },
      { system_id: 'u2', id: 'u2', name: 'Bob', age: 25, system_version: '2-0', system_created_at: '2-0', system_is_local_origin: 0 },
      { system_id: 'u3', id: 'u3', name: 'Charlie', age: 35, system_version: '3-0', system_created_at: '3-0', system_is_local_origin: 0 }
    ]);
    
    // Wait for automatic refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Should have automatically received update with bulk loaded data
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(3);
    expect(emissions[1][0].name).toBe('Alice');
    expect(emissions[1][1].name).toBe('Bob');
    expect(emissions[1][2].name).toBe('Charlie');
  });

  it('automatically pushes updates on bulkLoad updates', async () => {
    // Insert initial data
    await db.insert('users', { id: 'u1', name: 'Alice', age: 30 });
    
    // Create stream
    const stream = db.stream('users');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial emission
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    expect(emissions[0]).toHaveLength(1);
    expect(emissions[0][0].name).toBe('Alice');
    
    // Get the system_id and version from the inserted record
    const existing = await db.queryOne('users', { where: 'id = ?', whereArgs: ['u1'] });
    const systemId = existing!.system_id;
    const existingVersion = existing!.system_version;
    
    // Create a newer HLC by using db.hlc
    const hlc = db.hlc.now();
    const newerVersion = db.hlc.constructor.toString(hlc);
    
    // Bulk load with updated data - should auto-notify stream
    await db.bulkLoad('users', [
      { system_id: systemId, id: 'u1', name: 'Alice Updated', age: 31, system_version: newerVersion, system_created_at: existingVersion, system_is_local_origin: 0 }
    ]);
    
    // Wait for automatic refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Should have automatically received update
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(1);
    expect(emissions[1][0].name).toBe('Alice Updated');
    expect(emissions[1][0].age).toBe(31);
  });

  it('handles case-insensitive table names for stream notifications', async () => {
    // Create stream with lowercase table name
    const stream = db.stream('users');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial empty emission
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    expect(emissions[0]).toEqual([]);
    
    // Insert with UPPERCASE table name - should still notify lowercase stream
    await db.insert('USERS', { id: 'u1', name: 'Alice', age: 30 });
    
    // Wait for automatic refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Should have automatically received update despite case mismatch
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(1);
    expect(emissions[1][0].name).toBe('Alice');
  });

  it('handles mixed case in bulkLoad notifications', async () => {
    // Create stream with UPPERCASE
    const stream = db.stream('USERS');
    
    const emissions: any[][] = [];
    stream.subscribe(data => {
      emissions.push(data);
    });
    
    // Wait for initial empty emission
    await new Promise(resolve => setTimeout(resolve, 50));
    expect(emissions).toHaveLength(1);
    
    // BulkLoad with lowercase - should notify UPPERCASE stream
    await db.bulkLoad('users', [
      { system_id: 'u1', id: 'u1', name: 'Bob', age: 25, system_version: '1-0', system_created_at: '1-0', system_is_local_origin: 0 }
    ]);
    
    // Wait for automatic refresh
    await new Promise(resolve => setTimeout(resolve, 50));
    
    // Should have received update
    expect(emissions).toHaveLength(2);
    expect(emissions[1]).toHaveLength(1);
    expect(emissions[1][0].name).toBe('Bob');
  });
});
