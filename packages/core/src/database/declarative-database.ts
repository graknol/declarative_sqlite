import { SQLiteAdapter } from '../adapters/adapter.interface';
import { Schema } from '../schema/types';
import { SchemaMigrator } from '../migration/schema-migrator';
import { StreamingQuery, QueryOptions as StreamQueryOptions } from '../streaming/streaming-query';
import { QueryStreamManager } from '../streaming/query-stream-manager';
import { DbRecord } from '../records/db-record';
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

    await this.dirtyRowStore.init();

    this.isInitialized = true;
  }

  /**
   * Insert a record into a table
   */
  async insert(table: string, values: Record<string, any>, options?: InsertOptions): Promise<number> {
    this.ensureInitialized();

    const columns = Object.keys(values);
    const placeholders = columns.map(() => '?').join(', ');
    const columnList = columns.map(c => `"${c}"`).join(', ');

    const sql = options?.orReplace
      ? `INSERT OR REPLACE INTO "${table}" (${columnList}) VALUES (${placeholders})`
      : `INSERT INTO "${table}" (${columnList}) VALUES (${placeholders})`;

    const stmt = this.adapter.prepare(sql);
    const result = await stmt.run(...Object.values(values));
    
    // Notify streaming queries
    this.streamManager.notifyTableChanged(table);
    
    return Number(result.lastInsertRowid);
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

    const columns = Object.keys(values);
    const setClause = columns.map(c => `"${c}" = ?`).join(', ');

    let sql = `UPDATE "${table}" SET ${setClause}`;
    const params: any[] = Object.values(values);

    if (options?.where) {
      sql += ` WHERE ${options.where}`;
      if (options.whereArgs) {
        params.push(...options.whereArgs);
      }
    }

    const stmt = this.adapter.prepare(sql);
    const result = await stmt.run(...params);
    
    // Notify streaming queries
    this.streamManager.notifyTableChanged(table);
    
    return result.changes;
  }

  /**
   * Delete records from a table
   */
  async delete(table: string, options?: DeleteOptions): Promise<number> {
    this.ensureInitialized();

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
    
    // Notify streaming queries
    this.streamManager.notifyTableChanged(table);
    
    return result.changes;
  }

  /**
   * Query records from a table
   */
  async query<T extends Record<string, any> = any>(table: string, options?: QueryOptions): Promise<(T & DbRecord<T>)[]> {
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
    return results.map(row => DbRecord.create<T>(this, table, row));
  }

  /**
   * Query a single record from a table
   */
  async queryOne<T extends Record<string, any> = any>(table: string, options?: QueryOptions): Promise<(T & DbRecord<T>) | null> {
    const results = await this.query<T>(table, { ...options, limit: 1 });
    return results.length > 0 ? results[0]! : null;
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
   * Create a new DbRecord instance
   */
  createRecord<T extends Record<string, any>>(tableName: string, initialData?: Partial<T>): DbRecord<T> & T {
    this.ensureInitialized();
    return DbRecord.create<T>(this, tableName, initialData);
  }

  /**
   * Load an existing record by ID
   */
  async loadRecord<T extends Record<string, any>>(tableName: string, id: string): Promise<DbRecord<T> & T> {
    this.ensureInitialized();
    const row = await this.queryOne<T>(tableName, { where: 'id = ?', whereArgs: [id] });
    if (!row) {
      throw new Error(`Record not found: ${tableName} with id=${id}`);
    }
    return row;
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
    
    const tableDef = this.schema.tables.find(t => t.name === tableName);
    if (!tableDef) {
      throw new Error(`Table not found: ${tableName}`);
    }

    const pkColumns = tableDef.keys
      .filter(k => k.type === 'PRIMARY')
      .flatMap(k => k.columns);
      
    const lwwColumns = tableDef.columns
      .filter(c => c.lww)
      .map(c => c.name);

    for (const row of rows) {
      const systemId = row['system_id'];
      if (!systemId) continue;

      const existing = await this.queryOne(tableName, {
        where: 'system_id = ?',
        whereArgs: [systemId]
      });

      if (existing) {
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

              if (!localHlc || Hlc.compare(remoteHlc, localHlc) > 0) {
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
          try {
            // We need to update system_version as well
            valuesToUpdate['system_version'] = Hlc.toString(now);
            
            await this.update(tableName, valuesToUpdate, {
              where: 'system_id = ?',
              whereArgs: [systemId]
            });
          } catch (e) {
            if (this._isConstraintViolation(e)) {
              if (onConstraintViolation === ConstraintViolationStrategy.ThrowException) {
                throw e;
              }
              // Skip
            } else {
              throw e;
            }
          }
        }
      } else {
        // INSERT logic
        try {
          await this._insertFromServer(tableName, row);
        } catch (e) {
          if (this._isConstraintViolation(e)) {
            if (onConstraintViolation === ConstraintViolationStrategy.ThrowException) {
              throw e;
            }
            // Skip
          } else {
            throw e;
          }
        }
      }
    }
    
    this.streamManager.notifyTableChanged(tableName);
  }

  private async _insertFromServer(tableName: string, values: Record<string, any>): Promise<void> {
    const valuesToInsert = { ...values };
    const now = this.hlc.now();
    const nowString = Hlc.toString(now);

    // Add system columns if missing
    if (!valuesToInsert['system_version']) valuesToInsert['system_version'] = nowString;
    if (!valuesToInsert['system_created_at']) valuesToInsert['system_created_at'] = nowString;
    
    // Mark as server origin
    valuesToInsert['system_is_local_origin'] = 0;

    // Ensure LWW columns have HLCs if not provided
    const tableDef = this.schema.tables.find(t => t.name === tableName);
    if (tableDef) {
      for (const col of tableDef.columns) {
        if (col.lww && !valuesToInsert[`${col.name}__hlc`]) {
          valuesToInsert[`${col.name}__hlc`] = nowString;
        }
      }
    }

    await this.insert(tableName, valuesToInsert);
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
