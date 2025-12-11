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
  }

  /**
   * Create a proxied instance of DbRecord
   */
  static create<T extends Record<string, any>>(
    db: DeclarativeDatabase, 
    tableName: string, 
    initialData?: Partial<T & { system_id?: string }>
  ): DbRecord<T> & T {
    const record = new DbRecord<T>(db, tableName, initialData);

    // Return Proxy that intercepts property access
    return new Proxy(record, {
      get: (target, prop: string) => {
        // Allow access to methods
        if (prop in target || typeof (target as any)[prop] === 'function') {
          return (target as any)[prop];
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
      const systemId = await this._db.insert(this._tableName, allValues);
      
      // Update system_id if it wasn't present
      if (!this._values['system_id']) {
        this._values['system_id'] = systemId;
      }
      
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

  /**
   * Serialize DbRecord to a plain object for transmission across boundaries (e.g., Comlink).
   * This returns all data and metadata needed to reconstruct a read-only version.
   */
  toSerializable(): SerializableDbRecord {
    return {
      __type: 'SerializableDbRecord',
      tableName: this._tableName,
      values: { ...this._values },
      isNew: this._isNew,
      dirtyFields: Array.from(this._dirtyFields)
    };
  }

  /**
   * Create a read-only DbRecord-like object from serialized data.
   * This is useful when receiving DbRecord data from another context (e.g., web worker).
   * The returned object contains all data but methods that require database access will throw.
   */
  static fromSerializable(data: SerializableDbRecord): ReadonlyDbRecord {
    if (data.__type !== 'SerializableDbRecord') {
      throw new Error('Invalid serialized DbRecord data');
    }

    const readonlyRecord: ReadonlyDbRecord = {
      ...data.values,
      toJSON: () => ({ ...data.values }),
      isDirty: () => data.dirtyFields.length > 0,
      getDirtyFields: () => [...data.dirtyFields],
      // Methods that require database access throw helpful errors
      save: async () => {
        throw new Error('Cannot call save() on a read-only DbRecord from serialized data. Use database.insert() or database.update() instead.');
      },
      delete: async () => {
        throw new Error('Cannot call delete() on a read-only DbRecord from serialized data. Use database.delete() instead.');
      },
      __readonly: true,
      __tableName: data.tableName,
      __isNew: data.isNew
    };

    return readonlyRecord;
  }
}

/**
 * Serializable representation of a DbRecord for transmission across boundaries.
 */
export interface SerializableDbRecord {
  __type: 'SerializableDbRecord';
  tableName: string;
  values: Record<string, any>;
  isNew: boolean;
  dirtyFields: string[];
}

/**
 * Read-only representation of a DbRecord from serialized data.
 * Contains all data but methods requiring database access will throw.
 */
export interface ReadonlyDbRecord {
  [key: string]: any;
  toJSON: () => Record<string, any>;
  isDirty: () => boolean;
  getDirtyFields: () => string[];
  save: () => Promise<void>;
  delete: () => Promise<void>;
  __readonly: true;
  __tableName: string;
  __isNew: boolean;
}
