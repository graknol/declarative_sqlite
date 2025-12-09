import { IFileRepository, FileMetadata } from './file-repository.interface';
import { SQLiteAdapter } from '../adapters/adapter.interface';
import { Hlc } from '../sync/hlc';

export class MemoryFileRepository implements IFileRepository {
  private files = new Map<string, Uint8Array>();

  constructor(
    private adapter: SQLiteAdapter,
    private hlc: Hlc
  ) {}

  async addFile(fileset: string, filename: string, content: Uint8Array, mimeType?: string): Promise<string> {
    const fileId = `file-${Math.random().toString(36).substring(2, 15)}`;
    this.files.set(fileId, content);

    const timestamp = this.hlc.now();
    const timestampStr = Hlc.toString(timestamp);

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
      `memory://${fileId}`
    );
    await stmt.finalize();

    return fileId;
  }

  async getFileContent(fileId: string): Promise<Uint8Array> {
    const content = this.files.get(fileId);
    if (!content) {
      throw new Error(`File not found: ${fileId}`);
    }
    return content;
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
    this.files.delete(fileId);
    
    const stmt = await this.adapter.prepare(`
      DELETE FROM "__files" WHERE "id" = ?
    `);
    await stmt.run(fileId);
    await stmt.finalize();
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
