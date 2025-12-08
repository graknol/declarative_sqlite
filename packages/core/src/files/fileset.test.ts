import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { SqliteWasmAdapter } from '../database/sqlite-wasm-adapter';
import { Hlc } from '../sync/hlc';
import { IndexedDBFileRepository } from './indexeddb-file-repository';
import { FileSet } from './fileset';

describe('FileSet', () => {
  let adapter: SqliteWasmAdapter;
  let hlc: Hlc;
  let repository: IndexedDBFileRepository;

  beforeEach(async () => {
    // Create adapter
    adapter = new SqliteWasmAdapter();
    await adapter.open(':memory:');

    // Create __files table
    await adapter.exec(`
      CREATE TABLE "__files" (
        "id" TEXT PRIMARY KEY,
        "fileset" TEXT NOT NULL,
        "filename" TEXT NOT NULL,
        "mime_type" TEXT,
        "size" INTEGER NOT NULL,
        "created_at" TEXT NOT NULL,
        "modified_at" TEXT NOT NULL,
        "version" INTEGER NOT NULL,
        "storage_path" TEXT NOT NULL
      )
    `);

    // Create HLC
    hlc = new Hlc('test-node');

    // Create repository with unique database name for each test
    const dbName = `test-files-${Date.now()}`;
    repository = new IndexedDBFileRepository(adapter, hlc, dbName);
  });

  afterEach(async () => {
    await adapter.close();
  });

  it('should add files to fileset', async () => {
    const fileset = new FileSet(repository, 'documents');

    const content = new TextEncoder().encode('Hello World');
    const fileId = await fileset.addFile('test.txt', content, 'text/plain');

    expect(fileId).toMatch(/^file-/);

    const files = await fileset.listFiles();
    expect(files).toHaveLength(1);
    expect(files[0].filename).toBe('test.txt');
    expect(files[0].mimeType).toBe('text/plain');
    expect(files[0].size).toBe(content.length);
  });

  it('should get file content', async () => {
    const fileset = new FileSet(repository, 'documents');

    const content = new TextEncoder().encode('Hello World');
    const fileId = await fileset.addFile('test.txt', content);

    const retrieved = await fileset.getFile(fileId);
    const text = new TextDecoder().decode(retrieved);
    expect(text).toBe('Hello World');
  });

  it('should delete files', async () => {
    const fileset = new FileSet(repository, 'documents');

    const content = new TextEncoder().encode('Hello World');
    const fileId = await fileset.addFile('test.txt', content);

    await fileset.deleteFile(fileId);

    const files = await fileset.listFiles();
    expect(files).toHaveLength(0);
  });

  it('should enforce max file count', async () => {
    const fileset = new FileSet(repository, 'documents', 2); // Max 2 files

    const content = new TextEncoder().encode('Hello');

    await fileset.addFile('file1.txt', content);
    await fileset.addFile('file2.txt', content);

    // Third file should fail
    await expect(fileset.addFile('file3.txt', content)).rejects.toThrow(
      "already has maximum 2 files"
    );
  });

  it('should enforce max file size', async () => {
    const fileset = new FileSet(
      repository,
      'documents',
      undefined,
      100 // Max 100 bytes
    );

    const smallContent = new TextEncoder().encode('Small');
    await fileset.addFile('small.txt', smallContent);

    const largeContent = new Uint8Array(200); // 200 bytes
    await expect(fileset.addFile('large.txt', largeContent)).rejects.toThrow(
      'exceeds maximum 100 bytes'
    );
  });

  it('should list multiple files', async () => {
    const fileset = new FileSet(repository, 'documents');

    const content1 = new TextEncoder().encode('File 1');
    const content2 = new TextEncoder().encode('File 2');
    const content3 = new TextEncoder().encode('File 3');

    await fileset.addFile('file1.txt', content1);
    await fileset.addFile('file2.txt', content2);
    await fileset.addFile('file3.txt', content3);

    const files = await fileset.listFiles();
    expect(files).toHaveLength(3);
    expect(files.map((f) => f.filename)).toEqual(['file1.txt', 'file2.txt', 'file3.txt']);
  });

  it('should track file count and capacity', async () => {
    const fileset = new FileSet(repository, 'documents', 5); // Max 5 files

    expect(await fileset.getFileCount()).toBe(0);
    expect(await fileset.isFull()).toBe(false);
    expect(await fileset.getRemainingCapacity()).toBe(5);

    const content = new TextEncoder().encode('Hello');
    await fileset.addFile('file1.txt', content);
    await fileset.addFile('file2.txt', content);

    expect(await fileset.getFileCount()).toBe(2);
    expect(await fileset.isFull()).toBe(false);
    expect(await fileset.getRemainingCapacity()).toBe(3);
  });

  it('should update file metadata', async () => {
    const fileset = new FileSet(repository, 'documents');

    const content = new TextEncoder().encode('Hello');
    const fileId = await fileset.addFile('old-name.txt', content, 'text/plain');

    await fileset.updateMetadata(fileId, {
      filename: 'new-name.txt',
      mimeType: 'text/markdown',
    });

    const files = await fileset.listFiles();
    expect(files[0].filename).toBe('new-name.txt');
    expect(files[0].mimeType).toBe('text/markdown');
    expect(files[0].version).toBe(2); // Version incremented
  });
});
