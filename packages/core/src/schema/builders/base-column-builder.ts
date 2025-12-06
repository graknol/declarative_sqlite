import type { DbColumn, ColumnType } from '../types';

/**
 * Base class for column builders
 */
export abstract class BaseColumnBuilder<TValue = any> {
  protected _notNull: boolean = false;
  protected _defaultValue?: TValue;
  protected _defaultFn?: () => TValue;
  protected _lww: boolean = false;
  protected _maxLength?: number;
  
  constructor(
    protected name: string,
    protected type: ColumnType
  ) {}
  
  /**
   * Mark column as NOT NULL with default value
   */
  notNull(defaultValue: TValue | (() => TValue)): this {
    this._notNull = true;
    
    if (typeof defaultValue === 'function') {
      this._defaultFn = defaultValue as () => TValue;
    } else {
      this._defaultValue = defaultValue;
    }
    
    return this;
  }
  
  /**
   * Enable Last-Write-Wins conflict resolution for this column
   * Creates an associated __hlc column automatically
   */
  lww(): this {
    this._lww = true;
    return this;
  }
  
  /**
   * Build the column definition
   */
  build(): DbColumn {
    return {
      name: this.name,
      type: this.type,
      notNull: this._notNull,
      defaultValue: this._defaultValue,
      defaultFn: this._defaultFn,
      lww: this._lww,
      maxLength: this._maxLength,
    };
  }
}
