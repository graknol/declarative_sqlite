import type { SQLiteAdapter } from '../adapters/adapter.interface';
import type { Hlc, HlcTimestamp } from '../sync/hlc';
import type { FileMetadata, IFileRepository } from './file-repository.interface';

/**
 * Browser-compatible file repository using IndexedDB for file storage
 * This implementation stores files in IndexedDB instead of the filesystem
 */
export class IndexedDBFileRepository implements IFileRepository {
  private dbName: string;
  private storeName = 'files';

  constructor(
    private adapter: SQLiteAdapter,
    private hlc: Hlc,
    dbName: string = 'declarative-sqlite-files'
  ) {
    this.dbName = dbName;
  }

  /**
   * Initialize IndexedDB database
   */
  private async getDB(): Promise<IDBDatabase> {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, 1);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result);

      request.onupgradeneeded = (event) => {
        const db = (event.target as IDBOpenDBRequest).result;
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName, { keyPath: 'id' });
        }
      };
    });
  }

  async addFile(
    fileset: string,
    filename: string,
    content: Uint8Array,
    mimeType?: string
  ): Promise<string> {
    // Generate file ID using Web Crypto API
    const fileId = `file-${crypto.randomUUID()}`;
    const timestamp = this.hlc.now();

    // Store file content in IndexedDB
    const db = await this.getDB();
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction([this.storeName], 'readwrite');
      const store = transaction.objectStore(this.storeName);
      const request = store.put({ id: fileId, content });

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve();
    });

    // Insert metadata into __files table
    const stmt = this.adapter.prepare(`
      INSERT INTO "__files" (
        "id", "fileset", "filename", "mime_type", "size",
        "created_at", "modified_at", "version", "storage_path"
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    await stmt.run(
      fileId,
      fileset,
      filename,
      mimeType || 'application/octet-stream',
      content.length,
      timestamp,
      timestamp,
      1,
      `indexeddb://${this.dbName}/${this.storeName}/${fileId}`
    );

    await stmt.finalize();
    return fileId;
  }

  async getFileContent(fileId: string): Promise<Uint8Array> {
    const db = await this.getDB();
    
    return new Promise((resolve, reject) => {
      const transaction = db.transaction([this.storeName], 'readonly');
      const store = transaction.objectStore(this.storeName);
      const request = store.get(fileId);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        if (request.result) {
          resolve(request.result.content);
        } else {
          reject(new Error(`File not found: ${fileId}`));
        }
      };
    });
  }

  async listFiles(fileset: string): Promise<FileMetadata[]> {
    const stmt = this.adapter.prepare(`
      SELECT * FROM "__files" WHERE "fileset" = ?
    `);

    const rows = await stmt.all<any>(fileset);
    await stmt.finalize();

    return rows.map(row => ({
      id: row.id,
      fileset: row.fileset,
      filename: row.filename,
      mimeType: row.mime_type,
      size: row.size,
      createdAt: row.created_at,
      modifiedAt: row.modified_at,
      version: row.version,
      storagePath: row.storage_path,
    }));
  }

  async deleteFile(fileId: string): Promise<void> {
    // Delete from IndexedDB
    const db = await this.getDB();
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction([this.storeName], 'readwrite');
      const store = transaction.objectStore(this.storeName);
      const request = store.delete(fileId);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve();
    });

    // Delete metadata from __files table
    const stmt = this.adapter.prepare(`
      DELETE FROM "__files" WHERE "id" = ?
    `);

    await stmt.run(fileId);
    await stmt.finalize();
  }

  async updateMetadata(
    fileId: string,
    updates: Partial<Pick<FileMetadata, 'filename' | 'mimeType'>>
  ): Promise<void> {
    const timestamp = this.hlc.now();
    const setClauses: string[] = [];
    const params: any[] = [];

    if (updates.filename !== undefined) {
      setClauses.push('"filename" = ?');
      params.push(updates.filename);
    }

    if (updates.mimeType !== undefined) {
      setClauses.push('"mime_type" = ?');
      params.push(updates.mimeType);
    }

    if (setClauses.length === 0) {
      return;
    }

    setClauses.push('"modified_at" = ?');
    params.push(timestamp);
    params.push(fileId);

    const stmt = this.adapter.prepare(`
      UPDATE "__files"
      SET ${setClauses.join(', ')}
      WHERE "id" = ?
    `);

    await stmt.run(...params);
    await stmt.finalize();
  }
}
