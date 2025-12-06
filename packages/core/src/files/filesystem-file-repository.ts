import * as fs from 'fs';
import * as path from 'path';
import type { SQLiteAdapter } from '../adapters/adapter.interface';
import type { Hlc, HlcTimestamp } from '../sync/hlc';
import type { FileMetadata, IFileRepository } from './file-repository.interface';

/**
 * File repository implementation using filesystem storage
 */
export class FilesystemFileRepository implements IFileRepository {
  constructor(
    private adapter: SQLiteAdapter,
    private hlc: Hlc,
    private baseDir: string
  ) {}

  async addFile(
    fileset: string,
    filename: string,
    content: Uint8Array,
    mimeType?: string
  ): Promise<string> {
    // Generate file ID
    const fileId = `file-${crypto.randomUUID()}`;
    const timestamp = this.hlc.now();

    // Create fileset directory if needed
    const filesetDir = path.join(this.baseDir, fileset);
    if (!fs.existsSync(filesetDir)) {
      fs.mkdirSync(filesetDir, { recursive: true });
    }

    // Determine file extension
    const ext = path.extname(filename);
    const storagePath = path.join(filesetDir, `${fileId}${ext}`);

    // Write file to disk
    fs.writeFileSync(storagePath, content);

    // Insert metadata into __files table
    const stmt = this.adapter.prepare(`
      INSERT INTO "__files" (
        "id", "fileset", "filename", "mime_type", "size",
        "created_at", "modified_at", "version", "storage_path"
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    await stmt.run([
      fileId,
      fileset,
      filename,
      mimeType || null,
      content.length,
      this.hlcToString(timestamp),
      this.hlcToString(timestamp),
      1,
      storagePath,
    ]);

    return fileId;
  }

  async getFileContent(fileId: string): Promise<Uint8Array> {
    // Get file metadata
    const stmt = this.adapter.prepare(
      'SELECT "storage_path" FROM "__files" WHERE "id" = ?'
    );
    const row = await stmt.get([fileId]) as { storage_path: string } | undefined;

    if (!row) {
      throw new Error(`File not found: ${fileId}`);
    }

    // Read file from disk
    const content = fs.readFileSync(row.storage_path);
    return new Uint8Array(content);
  }

  async listFiles(fileset: string): Promise<FileMetadata[]> {
    const stmt = this.adapter.prepare(`
      SELECT * FROM "__files"
      WHERE "fileset" = ?
      ORDER BY "created_at" ASC
    `);

    const rows = await stmt.all([fileset]) as any[];

    return rows.map((row) => ({
      id: row.id,
      fileset: row.fileset,
      filename: row.filename,
      mimeType: row.mime_type || undefined,
      size: row.size,
      createdAt: this.parseHlc(row.created_at),
      modifiedAt: this.parseHlc(row.modified_at),
      version: row.version,
      storagePath: row.storage_path,
    }));
  }

  async deleteFile(fileId: string): Promise<void> {
    // Get file metadata
    const stmt = this.adapter.prepare(
      'SELECT "storage_path" FROM "__files" WHERE "id" = ?'
    );
    const row = await stmt.get([fileId]) as { storage_path: string } | undefined;

    if (!row) {
      throw new Error(`File not found: ${fileId}`);
    }

    // Delete file from disk
    if (fs.existsSync(row.storage_path)) {
      fs.unlinkSync(row.storage_path);
    }

    // Delete metadata
    const deleteStmt = this.adapter.prepare('DELETE FROM "__files" WHERE "id" = ?');
    await deleteStmt.run([fileId]);
  }

  async updateMetadata(
    fileId: string,
    updates: Partial<Pick<FileMetadata, 'filename' | 'mimeType'>>
  ): Promise<void> {
    const timestamp = this.hlc.now();
    const setClauses: string[] = [];
    const values: any[] = [];

    if (updates.filename !== undefined) {
      setClauses.push('"filename" = ?');
      values.push(updates.filename);
    }

    if (updates.mimeType !== undefined) {
      setClauses.push('"mime_type" = ?');
      values.push(updates.mimeType);
    }

    if (setClauses.length === 0) {
      return;
    }

    setClauses.push('"modified_at" = ?');
    values.push(this.hlcToString(timestamp));

    setClauses.push('"version" = "version" + 1');

    values.push(fileId);

    const sql = `
      UPDATE "__files"
      SET ${setClauses.join(', ')}
      WHERE "id" = ?
    `;

    const stmt = this.adapter.prepare(sql);
    await stmt.run(values);
  }

  private hlcToString(timestamp: HlcTimestamp): string {
    return `${timestamp.milliseconds}:${timestamp.counter}:${timestamp.nodeId}`;
  }

  private parseHlc(str: string): HlcTimestamp {
    const parts = str.split(':');
    return {
      milliseconds: parseInt(parts[0], 10),
      counter: parseInt(parts[1], 10),
      nodeId: parts[2],
    };
  }
}
