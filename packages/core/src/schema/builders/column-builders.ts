import { BaseColumnBuilder } from './base-column-builder';

/**
 * Builder for TEXT columns
 */
export class TextColumnBuilder extends BaseColumnBuilder<string> {
  constructor(name: string) {
    super(name, 'TEXT');
  }
  
  /**
   * Set maximum length for text column
   */
  maxLength(length: number): this {
    this._maxLength = length;
    return this;
  }
}

/**
 * Builder for INTEGER columns
 */
export class IntegerColumnBuilder extends BaseColumnBuilder<number> {
  constructor(name: string) {
    super(name, 'INTEGER');
  }
}

/**
 * Builder for REAL (float) columns
 */
export class RealColumnBuilder extends BaseColumnBuilder<number> {
  constructor(name: string) {
    super(name, 'REAL');
  }
}

/**
 * Builder for GUID columns
 */
export class GuidColumnBuilder extends BaseColumnBuilder<string> {
  constructor(name: string) {
    super(name, 'GUID');
  }
}

/**
 * Builder for DATE columns
 */
export class DateColumnBuilder extends BaseColumnBuilder<string> {
  constructor(name: string) {
    super(name, 'DATE');
  }
}

/**
 * Builder for FILESET columns
 */
export class FilesetColumnBuilder extends BaseColumnBuilder<any> {
  private _maxFileCount?: number;
  private _maxFileSize?: number;
  
  constructor(name: string) {
    super(name, 'FILESET');
  }
  
  /**
   * Set maximum number of files
   */
  max(count: number): this {
    this._maxFileCount = count;
    return this;
  }
  
  /**
   * Set maximum file size in bytes
   */
  maxFileSize(bytes: number): this {
    this._maxFileSize = bytes;
    return this;
  }
  
  /**
   * Helper to set max file size in MB
   */
  get maxFileSizeMB(): { mb: (megabytes: number) => FilesetColumnBuilder } {
    return {
      mb: (megabytes: number) => this.maxFileSize(megabytes * 1024 * 1024)
    };
  }
  
  override build() {
    const column = super.build();
    column.maxFileCount = this._maxFileCount;
    column.maxFileSize = this._maxFileSize;
    return column;
  }
}
