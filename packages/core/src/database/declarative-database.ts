import { SQLiteAdapter } from '../adapters/adapter.interface';
import { Schema } from '../schema/types';
import { SchemaMigrator } from '../migration/schema-migrator';
import { StreamingQuery, QueryOptions as StreamQueryOptions } from '../streaming/streaming-query';
import { QueryStreamManager } from '../streaming/query-stream-manager';
import { FileSet } from '../files/fileset';
import { Hlc, HlcTimestamp } from '../sync/hlc';
import { DirtyRowStore, SqliteDirtyRowStore } from '../sync/dirty-row-store';

export interface DatabaseConfig {
  adapter: SQLiteAdapter;
  schema: Schema;
  autoMigrate?: boolean;
  nodeId?: string;
  hlc?: Hlc;
  dirtyRowStore?: DirtyRowStore;
}

export interface InsertOptions {
  orReplace?: boolean;
}

export interface UpdateOptions {
  where?: string;
  whereArgs?: any[];
}

export interface DeleteOptions {
  where?: string;
  whereArgs?: any[];
}

export interface QueryOptions {
  where?: string;
  whereArgs?: any[];
  orderBy?: string;
  limit?: number;
  offset?: number;
}

export enum ConstraintViolationStrategy {
  ThrowException = 'throwException',
  Skip = 'skip',
}

/**
 * Main database class providing CRUD operations and schema management
 */
export class DeclarativeDatabase {
  private adapter: SQLiteAdapter;
  public schema: Schema;
  private autoMigrate: boolean;
  private isInitialized = false;
  private streamManager: QueryStreamManager;
  public hlc: Hlc;
  public dirtyRowStore: DirtyRowStore;

  constructor(config: DatabaseConfig) {
    this.adapter = config.adapter;
    this.schema = config.schema;
    this.autoMigrate = config.autoMigrate ?? true;
    this.streamManager = new QueryStreamManager();
    
    if (config.hlc) {
      this.hlc = config.hlc;
    } else {
      const nodeId = config.nodeId || `node-${Math.random().toString(36).substring(2, 9)}`;
      this.hlc = new Hlc(nodeId);
    }

    this.dirtyRowStore = config.dirtyRowStore || new SqliteDirtyRowStore(this.adapter);
  }

  /**
   * Initialize the database and optionally run migrations
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    if (!this.adapter.isOpen()) {
      throw new Error('Database adapter is not open. Call adapter.open() first.');
    }

    if (this.autoMigrate) {
      const migrator = new SchemaMigrator(this.adapter);
      await migrator.migrate(this.schema);
    }

    this.isInitialized = true;
  }

  /**
   * Insert a record into a table
   */
  async insert(table: string, values: Record<string, any>, options?: InsertOptions): Promise<string> {
    this.ensureInitialized();

    const now = this.hlc.now();
    const hlcString = Hlc.toString(now);
    
    // Prepare values with system columns (filter out tracking properties)
    const valuesToInsert = this._extractRecordData(values);
    
    if (!valuesToInsert['system_id']) {
      valuesToInsert['system_id'] = crypto.randomUUID();
    }
    if (!valuesToInsert['system_created_at']) {
      valuesToInsert['system_created_at'] = hlcString;
    }
    valuesToInsert['system_version'] = hlcString;
    
    if (valuesToInsert['system_is_local_origin'] === undefined) {
      valuesToInsert['system_is_local_origin'] = 1;
    }

    // Handle LWW columns (if not already set)
    const tableDef = this.schema.tables.find(t => t.name === table);
    if (tableDef) {
      for (const col of tableDef.columns) {
        if (col.lww) {
          const hlcCol = `${col.name}__hlc`;
          if (!valuesToInsert[hlcCol]) {
            valuesToInsert[hlcCol] = hlcString;
          }
        }
      }
    }

    const columns = Object.keys(valuesToInsert);
    const placeholders = columns.map(() => '?').join(', ');
    const columnList = columns.map(c => `"${c}"`).join(', ');

    const sql = options?.orReplace
      ? `INSERT OR REPLACE INTO "${table}" (${columnList}) VALUES (${placeholders})`
      : `INSERT INTO "${table}" (${columnList}) VALUES (${placeholders})`;

    const stmt = this.adapter.prepare(sql);
    await stmt.run(...Object.values(valuesToInsert));
    
    // Mark dirty
    await this.dirtyRowStore.markDirty({
      tableName: table,
      rowId: valuesToInsert['system_id'],
      hlc: hlcString,
      isFullRow: true
    });
    
    // Notify streaming queries
    this.streamManager.notifyTableChanged(table);
    
    return valuesToInsert['system_id'];
  }

  /**
   * Insert multiple records in a single transaction
   */
  async insertMany(table: string, records: Record<string, any>[], options?: InsertOptions): Promise<void> {
    this.ensureInitialized();

    await this.transaction(async () => {
      for (const record of records) {
        await this.insert(table, record, options);
      }
    });
  }

  /**
   * Update records in a table
   */
  async update(table: string, values: Record<string, any>, options?: UpdateOptions): Promise<number> {
    this.ensureInitialized();

    // 1. Find rows to update to get their system_ids
    let selectSql = `SELECT system_id, system_is_local_origin FROM "${table}"`;
    const selectParams: any[] = [];
    if (options?.where) {
      selectSql += ` WHERE ${options.where}`;
      if (options.whereArgs) {
        selectParams.push(...options.whereArgs);
      }
    }
    
    const selectStmt = this.adapter.prepare(selectSql);
    const rowsToUpdate = await selectStmt.all<{system_id: string, system_is_local_origin: number}>(...selectParams);
    
    if (rowsToUpdate.length === 0) {
      return 0;
    }

    const now = this.hlc.now();
    const hlcString = Hlc.toString(now);

    const valuesToUpdate = this._extractRecordData(values);
    valuesToUpdate['system_version'] = hlcString;

    // Handle LWW columns - update their __hlc timestamps
    const tableDef = this.schema.tables.find(t => t.name === table);
    if (tableDef) {
      for (const col of tableDef.columns) {
        if (col.lww && valuesToUpdate[col.name] !== undefined) {
          valuesToUpdate[`${col.name}__hlc`] = hlcString;
        }
      }
    }

    const columns = Object.keys(valuesToUpdate);
    const setClause = columns.map(c => `"${c}" = ?`).join(', ');

    let sql = `UPDATE "${table}" SET ${setClause}`;
    const params: any[] = Object.values(valuesToUpdate);

    if (options?.where) {
      sql += ` WHERE ${options.where}`;
      if (options.whereArgs) {
        params.push(...options.whereArgs);
      }
    }

    const stmt = this.adapter.prepare(sql);
    const result = await stmt.run(...params);
    
    // Mark dirty
    for (const row of rowsToUpdate) {
      await this.dirtyRowStore.markDirty({
        tableName: table,
        rowId: row.system_id,
        hlc: hlcString,
        isFullRow: row.system_is_local_origin === 1
      });
    }
    
    // Notify streaming queries
    this.streamManager.notifyTableChanged(table);
    
    return result.changes;
  }

  /**
   * Delete records from a table
   */
  async delete(table: string, options?: DeleteOptions): Promise<number> {
    this.ensureInitialized();

    // 1. Find rows to delete to get their system_ids
    let selectSql = `SELECT system_id, system_is_local_origin FROM "${table}"`;
    const selectParams: any[] = [];
    if (options?.where) {
      selectSql += ` WHERE ${options.where}`;
      if (options.whereArgs) {
        selectParams.push(...options.whereArgs);
      }
    }
    
    const selectStmt = this.adapter.prepare(selectSql);
    const rowsToDelete = await selectStmt.all<{system_id: string, system_is_local_origin: number}>(...selectParams);
    
    if (rowsToDelete.length === 0) {
      return 0;
    }

    const now = this.hlc.now();
    const hlcString = Hlc.toString(now);

    let sql = `DELETE FROM "${table}"`;
    const params: any[] = [];

    if (options?.where) {
      sql += ` WHERE ${options.where}`;
      if (options.whereArgs) {
        params.push(...options.whereArgs);
      }
    }

    const stmt = this.adapter.prepare(sql);
    const result = await stmt.run(...params);
    
    // Mark dirty
    for (const row of rowsToDelete) {
      await this.dirtyRowStore.markDirty({
        tableName: table,
        rowId: row.system_id,
        hlc: hlcString,
        isFullRow: row.system_is_local_origin === 1
      });
    }
    
    // Notify streaming queries
    this.streamManager.notifyTableChanged(table);
    
    return result.changes;
  }

  /**
   * Query records from a table (returns plain objects)
   */
  async query<T extends Record<string, any> = any>(table: string, options?: QueryOptions): Promise<T[]> {
    this.ensureInitialized();

    let sql = `SELECT * FROM "${table}"`;
    const params: any[] = [];

    if (options?.where) {
      sql += ` WHERE ${options.where}`;
      if (options?.whereArgs) {
        params.push(...options.whereArgs);
      }
    }

    if (options?.orderBy) {
      sql += ` ORDER BY ${options.orderBy}`;
    }

    if (options?.limit !== undefined) {
      sql += ` LIMIT ${options.limit}`;
    }

    if (options?.offset !== undefined) {
      sql += ` OFFSET ${options.offset}`;
    }

    const stmt = this.adapter.prepare(sql);
    const results = await stmt.all(...params);
    
    // Return plain objects with xRec property for change tracking
    return results.map(row => this._createRecordWithTracking<T>(table, row));
  }

  /**
   * Query a single record from a table (returns plain object)
   */
  async queryOne<T extends Record<string, any> = any>(table: string, options?: QueryOptions): Promise<T | null> {
    const results = await this.query<T>(table, { ...options, limit: 1 });
    return results.length > 0 ? results[0]! : null;
  }

  /**
   * Create a plain object with xRec property for change tracking
   * @internal
   */
  private _createRecordWithTracking<T extends Record<string, any>>(tableName: string, data: Record<string, any>): T {
    const record = { ...data } as any;
    // Store original values in xRec for change tracking
    Object.defineProperty(record, 'xRec', {
      value: { ...data },
      writable: false,
      enumerable: true,
      configurable: true  // Allow reconfiguring after save
    });
    Object.defineProperty(record, '__tableName', {
      value: tableName,
      writable: false,
      enumerable: true,
      configurable: false
    });
    return record;
  }

  /**
   * Execute a raw SQL query
   */
  async exec(sql: string): Promise<void> {
    this.ensureInitialized();
    await this.adapter.exec(sql);
  }

  /**
   * Execute a transaction
   */
  async transaction<T>(callback: () => Promise<T>): Promise<T> {
    this.ensureInitialized();
    return this.adapter.transaction(callback);
  }

  /**
   * Create a streaming query that automatically refreshes on data changes
   */
  stream<T extends Record<string, any> = any>(table: string, options?: StreamQueryOptions): StreamingQuery<T> {
    this.ensureInitialized();
    
    const stream = new StreamingQuery<T>(this, table, options);
    this.streamManager.registerStream(stream);
    
    return stream;
  }

  /**
   * Close the database
   */
  async close(): Promise<void> {
    this.streamManager.clear();
    await this.adapter.close();
    this.isInitialized = false;
  }

  /**
   * Export the database as a Uint8Array
   * Useful for downloading or backing up the database
   */
  async exportDatabase(): Promise<Uint8Array> {
    return await this.adapter.exportDatabase();
  }

  /**
   * Get the underlying adapter
   */
  getAdapter(): SQLiteAdapter {
    return this.adapter;
  }

  /**
   * Get the schema
   */
  getSchema(): Schema {
    return this.schema;
  }

  /**
   * Create a new record (returns plain object with xRec tracking)
   */
  createRecord<T extends Record<string, any>>(tableName: string, initialData?: Partial<T>): T {
    this.ensureInitialized();
    const data = initialData || {};
    return this._createRecordWithTracking<T>(tableName, data as Record<string, any>);
  }

  /**
   * Load an existing record by ID (returns plain object with xRec tracking)
   */
  async loadRecord<T extends Record<string, any>>(tableName: string, id: string): Promise<T> {
    this.ensureInitialized();
    const row = await this.queryOne<T>(tableName, { where: 'id = ?', whereArgs: [id] });
    if (!row) {
      throw new Error(`Record not found: ${tableName} with id=${id}`);
    }
    return row;
  }

  /**
   * Save a record (INSERT or UPDATE based on whether it's new)
   * Compares against xRec to determine changed fields for UPDATE
   */
  async save<T extends Record<string, any>>(record: T): Promise<string> {
    this.ensureInitialized();
    
    const tableName = (record as any).__tableName;
    if (!tableName) {
      throw new Error('Cannot save record without __tableName property. Use createRecord() or query() to get trackable records.');
    }
    
    const xRec = (record as any).xRec || {};
    const isNew = !xRec['system_id'] && !record['system_id'];
    
    if (isNew) {
      // INSERT: Create new record
      const values = this._extractRecordData(record);
      const systemId = await this.insert(tableName, values);
      
      // Re-fetch to get all system columns and update record
      const table = this.schema.tables.find(t => t.name === tableName);
      const primaryKey = table?.keys.find(k => k.type.toLowerCase() === 'primary');
      const pkColumn = primaryKey?.columns[0];
      
      if (pkColumn && values[pkColumn]) {
        const fresh = await this.queryOne(tableName, {
          where: `"${pkColumn}" = ?`,
          whereArgs: [values[pkColumn]]
        });
        if (fresh) {
          // Update record with fresh data
          Object.assign(record, fresh);
          // Update xRec to reflect saved state
          Object.defineProperty(record, 'xRec', {
            value: this._extractRecordData(fresh),
            writable: false,
            enumerable: true,
            configurable: true
          });
        }
      }
      
      return systemId;
    } else {
      // UPDATE: Only update changed fields
      const changes = this._getChangedFields(record, xRec);
      
      if (Object.keys(changes).length > 0) {
        const table = this.schema.tables.find(t => t.name === tableName);
        const primaryKey = table?.keys.find(k => k.type.toLowerCase() === 'primary');
        const pkColumn = primaryKey?.columns[0];
        
        if (pkColumn && record[pkColumn]) {
          await this.update(tableName, changes, {
            where: `"${pkColumn}" = ?`,
            whereArgs: [record[pkColumn]]
          });
          
          // Re-fetch to get updated system columns
          const fresh = await this.queryOne(tableName, {
            where: `"${pkColumn}" = ?`,
            whereArgs: [record[pkColumn]]
          });
          if (fresh) {
            // Update record with fresh data
            Object.assign(record, fresh);
            // Update xRec to reflect saved state
            Object.defineProperty(record, 'xRec', {
              value: this._extractRecordData(fresh),
              writable: false,
              enumerable: true,
              configurable: true
            });
          }
        }
      }
      
      return xRec['system_id'] || record['system_id'];
    }
  }

  /**
   * Delete a record from the database
   */
  async deleteRecord<T extends Record<string, any>>(record: T): Promise<void> {
    this.ensureInitialized();
    
    const tableName = (record as any).__tableName;
    if (!tableName) {
      throw new Error('Cannot delete record without __tableName property.');
    }
    
    const table = this.schema.tables.find(t => t.name === tableName);
    const primaryKey = table?.keys.find(k => k.type.toLowerCase() === 'primary');
    const pkColumn = primaryKey?.columns[0];
    
    if (pkColumn && record[pkColumn]) {
      await this.delete(tableName, {
        where: `"${pkColumn}" = ?`,
        whereArgs: [record[pkColumn]]
      });
    }
  }

  /**
   * Extract data fields from a record (excluding internal properties)
   * @internal
   */
  private _extractRecordData(record: Record<string, any>): Record<string, any> {
    const data: Record<string, any> = {};
    for (const key in record) {
      if (key !== 'xRec' && key !== '__tableName') {
        data[key] = record[key];
      }
    }
    return data;
  }

  /**
   * Get changed fields by comparing current record with xRec
   * @internal
   */
  private _getChangedFields(record: Record<string, any>, xRec: Record<string, any>): Record<string, any> {
    const changes: Record<string, any> = {};
    
    for (const key in record) {
      if (key === 'xRec' || key === '__tableName') continue;
      
      // Skip system columns that shouldn't be manually updated
      if (key === 'system_id' || key === 'system_created_at') continue;
      
      if (record[key] !== xRec[key]) {
        changes[key] = record[key];
        
        // Handle LWW columns - update HLC timestamp when value changes
        const tableName = (record as any).__tableName;
        const table = this.schema.tables.find(t => t.name === tableName);
        const column = table?.columns.find(c => c.name === key);
        
        if (column?.lww) {
          const hlcColumnName = `${key}__hlc`;
          const hlcColumn = table?.columns.find(c => c.name === hlcColumnName);
          
          if (hlcColumn) {
            const newHlc = this.hlc.now();
            const hlcString = Hlc.toString(newHlc);
            changes[hlcColumnName] = hlcString;
            record[hlcColumnName] = hlcString; // Update in record too
          }
        }
      }
    }
    
    return changes;
  }

  /**
   * Get a FileSet for a fileset column
   * @internal
   */
  getFileset(_tableName: string, _columnName: string, _recordId?: string): FileSet {
    // Placeholder - would integrate with FilesystemFileRepository
    throw new Error('FileSet integration not yet implemented');
  }

  /**
   * Bulk loads data into a table, performing an "upsert" operation.
   */
  async bulkLoad(
    tableName: string,
    rows: Record<string, any>[],
    onConstraintViolation: ConstraintViolationStrategy = ConstraintViolationStrategy.ThrowException
  ): Promise<void> {
    this.ensureInitialized();
    
    console.log(`[bulkLoad] Starting bulk load for table: ${tableName}, rows: ${rows.length}`);
    
    const tableDef = this.schema.tables.find(t => t.name === tableName);
    if (!tableDef) {
      const error = `Table not found: ${tableName}`;
      console.error(`[bulkLoad] ${error}`);
      throw new Error(error);
    }

    const pkColumns = tableDef.keys
      .filter(k => k.type === 'PRIMARY')
      .flatMap(k => k.columns);
      
    const lwwColumns = tableDef.columns
      .filter(c => c.lww)
      .map(c => c.name);

    console.log(`[bulkLoad] Table: ${tableName}, PK columns: [${pkColumns.join(', ')}], LWW columns: [${lwwColumns.join(', ')}]`);

    let processedCount = 0;
    let insertedCount = 0;
    let updatedCount = 0;
    let skippedCount = 0;

    for (const row of rows) {
      const systemId = row['system_id'];
      if (!systemId) {
        console.warn(`[bulkLoad] Row ${processedCount} has no system_id, skipping`);
        skippedCount++;
        processedCount++;
        continue;
      }

      console.log(`[bulkLoad] Processing row ${processedCount}: system_id=${systemId}`);

      const existing = await this.queryOne(tableName, {
        where: 'system_id = ?',
        whereArgs: [systemId]
      });

      if (existing) {
        console.log(`[bulkLoad] Row ${processedCount}: Found existing record, performing UPDATE`);
        // UPDATE logic
        const valuesToUpdate: Record<string, any> = {};
        const now = this.hlc.now();

        for (const [colName, value] of Object.entries(row)) {
          // Skip PKs, HLC columns, and system_is_local_origin
          if (pkColumns.includes(colName) || colName.endsWith('__hlc') || colName === 'system_is_local_origin') {
            continue;
          }

          if (lwwColumns.includes(colName)) {
            const hlcColName = `${colName}__hlc`;
            const remoteHlcString = row[hlcColName];

            if (remoteHlcString) {
              const localHlcValue = (existing as any)[hlcColName];
              let localHlc: HlcTimestamp | null = null;
              
              if (localHlcValue) {
                if (typeof localHlcValue === 'string') {
                  localHlc = Hlc.parse(localHlcValue);
                } else {
                  localHlc = localHlcValue as HlcTimestamp;
                }
              }
              
              const remoteHlc = Hlc.parse(remoteHlcString);

              // Per-column LWW comparison
              if (!localHlc || Hlc.compare(remoteHlc, localHlc) > 0) {
                // Server is newer for this column
                valuesToUpdate[colName] = value;
                valuesToUpdate[hlcColName] = remoteHlcString;
              }
            } else {
              // Server wins if no HLC provided (non-LWW update from server)
              valuesToUpdate[colName] = value;
            }
          } else {
            // Regular column, always update
            valuesToUpdate[colName] = value;
          }
        }

        if (Object.keys(valuesToUpdate).length > 0) {
          console.log(`[bulkLoad] Row ${processedCount}: ${Object.keys(valuesToUpdate).length} fields to update:`, Object.keys(valuesToUpdate));
          try {
            // We need to update system_version as well
            valuesToUpdate['system_version'] = Hlc.toString(now);
            
            // Use internal update to avoid marking as dirty
            await this._updateFromServer(tableName, valuesToUpdate, systemId);
            console.log(`[bulkLoad] Row ${processedCount}: UPDATE successful`);
            updatedCount++;
          } catch (e) {
            console.error(`[bulkLoad] Row ${processedCount}: UPDATE failed:`, e);
            if (this._isConstraintViolation(e)) {
              console.warn(`[bulkLoad] Row ${processedCount}: Constraint violation detected, strategy: ${onConstraintViolation}`);
              if (onConstraintViolation === ConstraintViolationStrategy.ThrowException) {
                throw e;
              }
              skippedCount++;
              // Skip
            } else {
              throw e;
            }
          }
        } else {
          console.log(`[bulkLoad] Row ${processedCount}: No fields to update (all values match existing or controlled by LWW)`);
        }
        
        // Check if we should clear the dirty mark by comparing system_version
        // against the dirty row's HLC timestamp
        const dirtyRow = await this.dirtyRowStore.getDirtyRow(tableName, systemId);
        if (dirtyRow) {
          // Get the server's system_version HLC
          const serverVersionString = row['system_version'];
          if (serverVersionString) {
            const serverVersion = Hlc.parse(serverVersionString);
            const dirtyRowHlc = Hlc.parse(dirtyRow.hlc);
            
            // If server's version is >= dirty row's timestamp, server is up-to-date
            if (Hlc.compare(serverVersion, dirtyRowHlc) >= 0) {
              await this.dirtyRowStore.clearDirty(tableName, systemId);
            }
          }
        }
      } else {
        console.log(`[bulkLoad] Row ${processedCount}: No existing record found, performing INSERT`);
        // INSERT logic
        try {
          await this._insertFromServer(tableName, row);
          console.log(`[bulkLoad] Row ${processedCount}: INSERT successful`);
          insertedCount++;
        } catch (e) {
          console.error(`[bulkLoad] Row ${processedCount}: INSERT failed:`, e);
          if (this._isConstraintViolation(e)) {
            console.warn(`[bulkLoad] Row ${processedCount}: Constraint violation detected, strategy: ${onConstraintViolation}`);
            if (onConstraintViolation === ConstraintViolationStrategy.ThrowException) {
              throw e;
            }
            skippedCount++;
            // Skip
          } else {
            throw e;
          }
        }
      }
      
      processedCount++;
    }
    
    console.log(`[bulkLoad] Completed: processed=${processedCount}, inserted=${insertedCount}, updated=${updatedCount}, skipped=${skippedCount}`);
    console.log(`[bulkLoad] Notifying stream manager for table: ${tableName}`);
    this.streamManager.notifyTableChanged(tableName);
  }

  private async _insertFromServer(tableName: string, values: Record<string, any>): Promise<void> {
    console.log(`[_insertFromServer] Table: ${tableName}, system_id: ${values['system_id']}`);
    const valuesToInsert = { ...values };
    const now = this.hlc.now();
    const nowString = Hlc.toString(now);

    // Add system columns if missing
    if (!valuesToInsert['system_version']) valuesToInsert['system_version'] = nowString;
    if (!valuesToInsert['system_created_at']) valuesToInsert['system_created_at'] = nowString;
    if (!valuesToInsert['system_id']) valuesToInsert['system_id'] = crypto.randomUUID();
    
    // Mark as server origin
    valuesToInsert['system_is_local_origin'] = 0;
    console.log(`[_insertFromServer] Columns to insert: ${Object.keys(valuesToInsert).length}`);

    // Ensure LWW columns have HLCs if not provided
    const tableDef = this.schema.tables.find(t => t.name === tableName);
    if (tableDef) {
      for (const col of tableDef.columns) {
        if (col.lww && !valuesToInsert[`${col.name}__hlc`]) {
          valuesToInsert[`${col.name}__hlc`] = nowString;
        }
      }
    }

    const columns = Object.keys(valuesToInsert);
    const placeholders = columns.map(() => '?').join(', ');
    const columnList = columns.map(c => `"${c}"`).join(', ');

    const sql = `INSERT INTO "${tableName}" (${columnList}) VALUES (${placeholders})`;
    console.log(`[_insertFromServer] Executing INSERT with ${columns.length} columns`);
    const stmt = this.adapter.prepare(sql);
    const result = await stmt.run(...Object.values(valuesToInsert));
    console.log(`[_insertFromServer] INSERT completed, changes: ${result.changes}`);
    
    // Don't mark as dirty - this came from the server
  }

  private async _updateFromServer(
    tableName: string,
    values: Record<string, any>,
    systemId: string
  ): Promise<void> {
    console.log(`[_updateFromServer] Table: ${tableName}, system_id: ${systemId}`);
    const columns = Object.keys(values);
    const setClause = columns.map(c => `"${c}" = ?`).join(', ');

    const sql = `UPDATE "${tableName}" SET ${setClause} WHERE system_id = ?`;
    const params = [...Object.values(values), systemId];

    console.log(`[_updateFromServer] Executing UPDATE with ${columns.length} columns`);
    const stmt = this.adapter.prepare(sql);
    const result = await stmt.run(...params);
    console.log(`[_updateFromServer] UPDATE completed, changes: ${result.changes}`);
    
    // Don't mark as dirty - this came from the server
  }

  private _isConstraintViolation(e: any): boolean {
    const msg = String(e).toLowerCase();
    return msg.includes('constraint') || msg.includes('unique');
  }

  private ensureInitialized(): void {
    if (!this.isInitialized) {
      throw new Error('Database not initialized. Call initialize() first.');
    }
  }
}
