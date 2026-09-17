import type { SqlValue } from '../types';
import { SchemaError, type ColumnDef, type LogicalType, type StorageType } from './types';

/**
 * Declares one column. Instances come from the table builder (`t.text('x')`),
 * never from application code directly, and every modifier returns `this` so
 * `.notNull('')`, `.maxLength(50)` and their reverse order all read the same.
 * `notNull` always takes the default value that existing rows get when the
 * column is added by an automatic migration — a NOT NULL column without one
 * cannot be added to a populated table.
 */
export class ColumnBuilder {
  private _notNull = false;
  private _defaultValue: SqlValue | undefined;
  private _maxLength: number | undefined;

  constructor(
    private readonly name: string,
    private readonly type: StorageType,
    private readonly logical: LogicalType,
  ) {}

  notNull(defaultValue: SqlValue): this {
    if (this.type === 'INTEGER' || this.type === 'REAL') {
      if (typeof defaultValue !== 'number') {
        throw new SchemaError(`Column ${this.name}: notNull() on a numeric column needs a number default, got ${typeof defaultValue}`);
      }
    } else if (this.type === 'TEXT' && typeof defaultValue !== 'string') {
      throw new SchemaError(`Column ${this.name}: notNull() on a text column needs a string default, got ${typeof defaultValue}`);
    }
    this._notNull = true;
    this._defaultValue = defaultValue;
    return this;
  }

  maxLength(length: number): this {
    if (!Number.isInteger(length) || length <= 0) {
      throw new SchemaError(`Column ${this.name}: maxLength must be a positive integer, got ${length}`);
    }
    this._maxLength = length;
    return this;
  }

  build(): ColumnDef {
    const def: ColumnDef = { name: this.name, type: this.type, logical: this.logical, notNull: this._notNull };
    if (this._defaultValue !== undefined) def.defaultValue = this._defaultValue;
    if (this._maxLength !== undefined) def.maxLength = this._maxLength;
    return def;
  }
}
