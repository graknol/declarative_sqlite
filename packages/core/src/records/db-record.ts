import type { DeclarativeDatabase } from '../database/declarative-database';
import type { FileSet } from '../files/fileset';
import { Hlc } from '../sync/hlc';

/**
 * Base class for database records with Proxy-based property access.
 * Eliminates the need for code generation while maintaining type safety.
 */
export class DbRecord<T extends Record<string, any>> {
  private _db: DeclarativeDatabase;
  private _tableName: string;
  private _values: Record<string, any> = {};
  private _dirtyFields: Set<string> = new Set();
  private _filesets: Map<string, FileSet> = new Map();
  private _isNew: boolean = true;
  
  constructor(db: DeclarativeDatabase, tableName: string, initialData?: Partial<T & { system_id?: string }>) {
    this._db = db;
    this._tableName = tableName;
    
    // Initialize with data if provided
    if (initialData) {
      Object.assign(this._values, initialData);
      // If system_id is present, this is an existing record
      if ((initialData as any).system_id) {
        this._isNew = false;
      }
    }
    
    // Return Proxy that intercepts property access
    return new Proxy(this, {
      get: (target, prop: string) => {
        // Allow access to methods
        if (prop in target || typeof (target as any)[prop] === 'function') {
          return (target as any)[prop];
        }
        
        // Handle system columns (read-only)
        if (prop.startsWith('system_')) {
          return target._values[prop];
        }
        
        // Handle LWW timestamp columns
        if (prop.endsWith('__hlc')) {
          const value = target._values[prop];
          return value ? (typeof value === 'string' ? Hlc.parse(value) : value) : undefined;
        }
        
        // Handle fileset columns
        const table = target._db.schema.tables.find(t => t.name === target._tableName);
        const column = table?.columns.find(c => c.name === prop);
        if (column && column.type === 'FILESET') {
          if (!target._filesets.has(prop)) {
            const fileset = target._db.getFileset(target._tableName, prop, target._values['system_id']);
            target._filesets.set(prop, fileset);
          }
          return target._filesets.get(prop);
        }
        
        // Handle regular columns
        return target._values[prop];
      },
      
      set: (target, prop: string, value: any) => {
        // Allow setting internal properties from within the class
        if (prop.startsWith('_')) {
          (target as any)[prop] = value;
          return true;
        }
        
        // Prevent setting system columns
        if (prop.startsWith('system_')) {
          throw new Error(`Cannot set system property: ${prop}`);
        }
        
        // Prevent setting LWW timestamp columns directly
        if (prop.endsWith('__hlc')) {
          throw new Error(`Cannot set LWW timestamp directly: ${prop}`);
        }
        
        // Set value and mark as dirty
        target._values[prop] = value;
        target._dirtyFields.add(prop);

        // Handle LWW columns - automatically update HLC timestamp
        const table = target._db.schema.tables.find(t => t.name === target._tableName);
        const column = table?.columns.find(c => c.name === prop);
        
        if (column?.lww) {
          const hlcColumnName = `${prop}__hlc`;
          // Check if the HLC column exists in the table
          const hlcColumn = table?.columns.find(c => c.name === hlcColumnName);
          
          if (hlcColumn) {
            const newHlc = target._db.hlc.now();
            const hlcString = Hlc.toString(newHlc);
            
            target._values[hlcColumnName] = hlcString;
            target._dirtyFields.add(hlcColumnName);
          }
        }

        return true;
      }
    }) as unknown as DbRecord<T> & T;
  }
  
  /**
   * Save the record to the database (INSERT or UPDATE).
   */
  async save(): Promise<void> {
    // Find the primary key column
    const table = this._db.schema.tables.find(t => t.name === this._tableName);
    const primaryKey = table?.keys.find(k => k.type.toLowerCase() === 'primary');
    const pkColumn = primaryKey?.columns[0]; // Assuming single-column PK for now
    
    if (this._isNew) {
      // INSERT: Create new record
      const allValues = { ...this._values };
      await this._db.insert(this._tableName, allValues);
      
      // Re-fetch to get system columns using the primary key
      if (pkColumn && this._values[pkColumn]) {
        const row = await this._db.queryOne(this._tableName, {
          where: `"${pkColumn}" = ?`,
          whereArgs: [this._values[pkColumn]]
        });
        if (row) {
          Object.assign(this._values, row.toJSON());
        }
      }
      // Mark as no longer new
      this._isNew = false;
    } else {
      // UPDATE: Update existing record
      if (this._dirtyFields.size > 0) {
        const updates: Record<string, any> = {};
        for (const field of this._dirtyFields) {
          updates[field] = this._values[field];
        }
        
        // Use primary key for WHERE clause
        if (pkColumn && this._values[pkColumn]) {
          await this._db.update(
            this._tableName,
            updates,
            { where: `"${pkColumn}" = ?`, whereArgs: [this._values[pkColumn]] }
          );
          
          // Re-fetch to get updated system columns
          const row = await this._db.queryOne(this._tableName, {
            where: `"${pkColumn}" = ?`,
            whereArgs: [this._values[pkColumn]]
          });
          if (row) {
            Object.assign(this._values, row.toJSON());
          }
        }
      }
    }
    
    // Clear dirty tracking
    this._dirtyFields.clear();
  }
  
  /**
   * Delete the record from the database.
   */
  async delete(): Promise<void> {
    // Find the primary key column
    const table = this._db.schema.tables.find(t => t.name === this._tableName);
    const primaryKey = table?.keys.find(k => k.type.toLowerCase() === 'primary');
    const pkColumn = primaryKey?.columns[0]; // Assuming single-column PK for now
    
    if (pkColumn && this._values[pkColumn]) {
      await this._db.delete(this._tableName, {
        where: `"${pkColumn}" = ?`,
        whereArgs: [this._values[pkColumn]]
      });
    }
  }
  
  /**
   * Check if the record has unsaved changes.
   */
  isDirty(): boolean {
    return this._dirtyFields.size > 0;
  }
  
  /**
   * Get list of fields that have been modified.
   */
  getDirtyFields(): string[] {
    return Array.from(this._dirtyFields);
  }
  
  /**
   * Get the underlying data values.
   */
  toJSON(): Record<string, any> {
    return { ...this._values };
  }
}
