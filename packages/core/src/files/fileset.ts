import type { FileMetadata, IFileRepository } from './file-repository.interface';

/**
 * High-level API for managing files in a fileset with constraints
 */
export class FileSet {
  constructor(
    private repository: IFileRepository,
    private filesetName: string,
    private maxFiles?: number,
    private maxFileSize?: number
  ) {}

  /**
   * Add a file to this fileset
   * @throws If max file count or max file size exceeded
   */
  async addFile(
    filename: string,
    content: Uint8Array,
    mimeType?: string
  ): Promise<string> {
    // Check file size constraint
    if (this.maxFileSize !== undefined && content.length > this.maxFileSize) {
      throw new Error(
        `File size ${content.length} bytes exceeds maximum ${this.maxFileSize} bytes`
      );
    }

    // Check file count constraint
    if (this.maxFiles !== undefined) {
      const existing = await this.repository.listFiles(this.filesetName);
      if (existing.length >= this.maxFiles) {
        throw new Error(
          `Fileset '${this.filesetName}' already has maximum ${this.maxFiles} files`
        );
      }
    }

    return this.repository.addFile(this.filesetName, filename, content, mimeType);
  }

  /**
   * List all files in this fileset
   */
  async listFiles(): Promise<FileMetadata[]> {
    return this.repository.listFiles(this.filesetName);
  }

  /**
   * Get file content by ID
   */
  async getFile(fileId: string): Promise<Uint8Array> {
    return this.repository.getFileContent(fileId);
  }

  /**
   * Delete a file from this fileset
   */
  async deleteFile(fileId: string): Promise<void> {
    return this.repository.deleteFile(fileId);
  }

  /**
   * Update file metadata
   */
  async updateMetadata(
    fileId: string,
    updates: Partial<Pick<FileMetadata, 'filename' | 'mimeType'>>
  ): Promise<void> {
    return this.repository.updateMetadata(fileId, updates);
  }

  /**
   * Get current file count
   */
  async getFileCount(): Promise<number> {
    const files = await this.listFiles();
    return files.length;
  }

  /**
   * Check if fileset is at capacity
   */
  async isFull(): Promise<boolean> {
    if (this.maxFiles === undefined) {
      return false;
    }
    const count = await this.getFileCount();
    return count >= this.maxFiles;
  }

  /**
   * Get remaining capacity
   */
  async getRemainingCapacity(): Promise<number | undefined> {
    if (this.maxFiles === undefined) {
      return undefined;
    }
    const count = await this.getFileCount();
    return Math.max(0, this.maxFiles - count);
  }
}
