import { fs } from '@zenfs/core';
import { IFileRepository, FileMetadata } from './file-repository.interface';
import { SQLiteAdapter } from '../adapters/adapter.interface';
import { Hlc } from '../sync/hlc';

/**
 * File repository implementation using ZenFS.
 * Supports multiple backends (OPFS, IndexedDB, Memory) via ZenFS configuration.
 */
export class ZenFSFileRepository implements IFileRepository {
  constructor(
    private adapter: SQLiteAdapter,
    private hlc: Hlc,
    private rootPath: string = '/files'
  ) {}

  private join(...parts: string[]): string {
    return parts.join('/').replace(/\/+/g, '/');
  }

  private async ensureDirectory(path: string): Promise<void> {
    try {
      await fs.promises.access(path);
    } catch {
      await fs.promises.mkdir(path, { recursive: true });
    }
  }

  async addFile(
    fileset: string,
    filename: string,
    content: Uint8Array,
    mimeType?: string
  ): Promise<string> {
    const fileId = `file-${crypto.randomUUID()}`;
    const timestamp = this.hlc.now();
    const timestampStr = Hlc.toString(timestamp);
    
    const filesetPath = this.join(this.rootPath, fileset);
    await this.ensureDirectory(filesetPath);
    
    const filePath = this.join(filesetPath, fileId);
    await fs.promises.writeFile(filePath, content);

    const stmt = await this.adapter.prepare(`
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
      timestampStr,
      timestampStr,
      1,
      `zenfs://${filePath}`
    );
    await stmt.finalize();

    return fileId;
  }

  async getFileContent(fileId: string): Promise<Uint8Array> {
    // We need to find the path. We can query the DB or reconstruct it if we know the structure.
    // The storage_path in DB is `zenfs://${filePath}`.
    // But for performance, we might want to avoid a DB query if possible.
    // However, the interface takes `fileId`.
    // In addFile, we stored it at `rootPath/fileset/fileId`.
    // But `getFileContent` only gets `fileId`.
    // We don't know the `fileset` from `fileId` alone without querying the DB.
    
    // Let's query the DB to get the path.
    const stmt = await this.adapter.prepare('SELECT storage_path FROM "__files" WHERE id = ?');
    const result = await stmt.get(fileId);
    await stmt.finalize();

    if (!result) {
      throw new Error(`File not found: ${fileId}`);
    }

    const storagePath = result.storage_path as string;
    if (!storagePath.startsWith('zenfs://')) {
      throw new Error(`Invalid storage path: ${storagePath}`);
    }

    const filePath = storagePath.substring('zenfs://'.length);
    const content = await fs.promises.readFile(filePath);
    return new Uint8Array(content);
  }

  async listFiles(fileset: string): Promise<FileMetadata[]> {
    const stmt = await this.adapter.prepare(`
      SELECT * FROM "__files" WHERE "fileset" = ?
    `);
    const rows = await stmt.all(fileset);
    await stmt.finalize();

    return rows.map((row: any) => ({
      id: row.id,
      fileset: row.fileset,
      filename: row.filename,
      mimeType: row.mime_type,
      size: row.size,
      createdAt: Hlc.parse(row.created_at),
      modifiedAt: Hlc.parse(row.modified_at),
      version: row.version,
      storagePath: row.storage_path,
    }));
  }

  async deleteFile(fileId: string): Promise<void> {
    // Get path first
    const stmt = await this.adapter.prepare('SELECT storage_path FROM "__files" WHERE id = ?');
    const result = await stmt.get(fileId);
    await stmt.finalize();

    if (result) {
      const storagePath = result.storage_path as string;
      if (storagePath.startsWith('zenfs://')) {
        const filePath = storagePath.substring('zenfs://'.length);
        try {
          await fs.promises.unlink(filePath);
        } catch (e) {
          // Ignore if file already missing
          console.warn(`Failed to delete file ${filePath}:`, e);
        }
      }
    }

    const delStmt = await this.adapter.prepare(`
      DELETE FROM "__files" WHERE "id" = ?
    `);
    await delStmt.run(fileId);
    await delStmt.finalize();
  }

  async updateMetadata(
    fileId: string,
    updates: Partial<Pick<FileMetadata, 'filename' | 'mimeType'>>
  ): Promise<void> {
    const sets: string[] = [];
    const args: any[] = [];

    if (updates.filename) {
      sets.push('"filename" = ?');
      args.push(updates.filename);
    }
    if (updates.mimeType) {
      sets.push('"mime_type" = ?');
      args.push(updates.mimeType);
    }

    if (sets.length === 0) return;

    const timestamp = this.hlc.now();
    sets.push('"modified_at" = ?');
    args.push(Hlc.toString(timestamp));

    args.push(fileId);

    const stmt = await this.adapter.prepare(`
      UPDATE "__files" SET ${sets.join(', ')} WHERE "id" = ?
    `);
    await stmt.run(...args);
    await stmt.finalize();
  }
}
