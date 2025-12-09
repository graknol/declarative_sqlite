import { describe, it, expect, beforeEach, afterEach, beforeAll } from 'vitest';
import { SqliteWasmAdapter } from '../database/sqlite-wasm-adapter';
import { Hlc } from '../sync/hlc';
import { FileSet } from './fileset';
import { ZenFSFileRepository } from './zenfs-file-repository';
import { DeclarativeDatabase } from '../database/declarative-database';
import { SchemaBuilder } from '../schema/builders/schema-builder';
import { configure, InMemory, fs } from '@zenfs/core';

describe('FileSet', () => {
  let adapter: SqliteWasmAdapter;
  let db: DeclarativeDatabase;
  let fileRepo: ZenFSFileRepository;
  let fileset: FileSet;
  let hlc: Hlc;

  beforeAll(async () => {
    // Configure ZenFS with InMemory backend for testing
    try {
      await configure({
        mounts: {
          '/files': { backend: InMemory, name: 'files' }
        }
      });
    } catch (e) {
      // Ignore if already configured
    }
  });

  beforeEach(async () => {
    // Clean up files
    try {
      const files = await fs.promises.readdir('/files');
      for (const file of files) {
        await fs.promises.unlink(`/files/${file}`);
      }
    } catch (e) {
      // Ignore
    }

    adapter = new SqliteWasmAdapter();
    await adapter.open(':memory:');
    
    const schema = new SchemaBuilder()
      .table('documents', t => {
        t.guid('id');
        t.fileset('attachments');
        t.key('id').primary();
      })
      .build();

    db = new DeclarativeDatabase({
      adapter,
      schema,
      autoMigrate: true,
    });
    await db.initialize();

    hlc = new Hlc('test-node');
    fileRepo = new ZenFSFileRepository(adapter, hlc, '/files');
    fileset = new FileSet(fileRepo, 'attachments');
  });

  afterEach(async () => {
    await db.close();
  });

  it('should add a file', async () => {
    const content = new TextEncoder().encode('Hello World');
    const fileId = await fileset.addFile('test.txt', content);
    
    expect(fileId).toBeDefined();
    
    const retrieved = await fileset.getFile(fileId);
    expect(new TextDecoder().decode(retrieved)).toBe('Hello World');
  });

  it('should track file metadata in database', async () => {
    const content = new TextEncoder().encode('Hello World');
    await fileset.addFile('test.txt', content);
    
    const files = await db.query('__files');
    expect(files).toHaveLength(1);
    expect(files[0].filename).toBe('test.txt');
    expect(files[0].fileset).toBe('attachments');
    expect(files[0].size).toBe(content.length);
  });

  it('should delete a file', async () => {
    const content = new TextEncoder().encode('Hello World');
    const fileId = await fileset.addFile('test.txt', content);
    
    await fileset.deleteFile(fileId);
    
    const files = await db.query('__files');
    expect(files).toHaveLength(0);
    
    await expect(fileset.getFile(fileId)).rejects.toThrow();
  });
});
