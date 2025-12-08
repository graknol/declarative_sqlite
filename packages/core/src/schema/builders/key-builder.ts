import type { DbKey, KeyType } from '../types';

/**
 * Builder for database keys (primary, unique, index)
 */
export class KeyBuilder {
  private _type: KeyType = 'INDEX';
  private _name?: string;
  
  constructor(private columns: string[]) {}
  
  /**
   * Mark as primary key
   */
  primary(): this {
    this._type = 'PRIMARY';
    return this;
  }
  
  /**
   * Mark as unique constraint
   */
  unique(): this {
    this._type = 'UNIQUE';
    return this;
  }
  
  /**
   * Mark as index (default)
   */
  index(): this {
    this._type = 'INDEX';
    return this;
  }
  
  /**
   * Set custom name for the key
   */
  name(name: string): this {
    this._name = name;
    return this;
  }
  
  /**
   * Build the key definition
   */
  build(): DbKey {
    return {
      columns: this.columns,
      type: this._type,
      name: this._name,
    };
  }
}
