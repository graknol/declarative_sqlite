import type { HlcTimestamp } from '../sync/hlc';

/**
 * File metadata stored in __files table
 */
export interface FileMetadata {
  id: string;
  fileset: string;
  filename: string;
  mimeType?: string;
  size: number;
  createdAt: HlcTimestamp;
  modifiedAt: HlcTimestamp;
  version: number;
  storagePath: string;
}

/**
 * Interface for file storage backends
 */
export interface IFileRepository {
  /**
   * Add a file to a fileset
   */
  addFile(
    fileset: string,
    filename: string,
    content: Uint8Array,
    mimeType?: string
  ): Promise<string>;

  /**
   * Get file content by ID
   */
  getFileContent(fileId: string): Promise<Uint8Array>;

  /**
   * List files in a fileset
   */
  listFiles(fileset: string): Promise<FileMetadata[]>;

  /**
   * Delete a file
   */
  deleteFile(fileId: string): Promise<void>;

  /**
   * Update file metadata
   */
  updateMetadata(
    fileId: string,
    updates: Partial<Pick<FileMetadata, 'filename' | 'mimeType'>>
  ): Promise<void>;
}
