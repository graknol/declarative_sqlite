import { SQLiteAdapter } from '../adapters/adapter.interface';
import { Schema } from '../schema/types';
import { SchemaMigrator } from '../migration/schema-migrator';

export interface DatabaseConfig {
  adapter: SQLiteAdapter;
  schema: Schema;
  autoMigrate?: boolean;
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

/**
 * Main database class providing CRUD operations and schema management
 */
export class DeclarativeDatabase {
  private adapter: SQLiteAdapter;
  private schema: Schema;
  private autoMigrate: boolean;
  private isInitialized = false;

  constructor(config: DatabaseConfig) {
    this.adapter = config.adapter;
    this.schema = config.schema;
    this.autoMigrate = config.autoMigrate ?? true;
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
    return result.changes;
  }

  /**
   * Query records from a table
   */
  async query<T = any>(table: string, options?: QueryOptions): Promise<T[]> {
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
    return results as T[];
  }

  /**
   * Query a single record from a table
   */
  async queryOne<T = any>(table: string, options?: QueryOptions): Promise<T | null> {
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
   * Close the database
   */
  async close(): Promise<void> {
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

  private ensureInitialized(): void {
    if (!this.isInitialized) {
      throw new Error('Database not initialized. Call initialize() first.');
    }
  }
}
