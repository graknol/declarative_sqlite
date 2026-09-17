import type { RunResult, SQLiteAdapter } from '../adapters/adapter';
import { runMigration, type MigrationMode, type MigrationPlan } from '../migration/migrate';
import { SYSTEM_ID_COLUMN } from '../schema/table-builder';
import type { Schema, TableDef } from '../schema/types';
import type { Row, SqlValue } from '../types';
import { InvalidationBus, WriteLog } from './invalidation-bus';
import { quoteIdentifier } from './sql';
import { writeRow, type RowMap, type SyncedTableApi, type TableApi, type TableApis } from './tables';
import { Transaction } from './transaction';

/** Everything `Database.open` needs: the declared schema, an adapter to run it on, and how much freedom the migration has. */
export interface DatabaseOptions {
  schema: Schema;
  adapter: SQLiteAdapter;
  /** `auto` (default) migrates on open, `plan` only reports, `off` assumes the database already matches. */
  migrate?: MigrationMode;
  /** Allows the guarded table rebuild a storage-type change needs. Default false. */
  allowRecreate?: boolean;
  onMigrationPlan?: (plan: MigrationPlan) => void;
}

/**
 * The database handle: opens an adapter, migrates it to the declared schema and
 * owns the single write path. Reads are SQL strings with positional parameters;
 * writes go through `db.tables` or a transaction, so that every commit produces
 * exactly one invalidation event. Nothing above this class executes SQL.
 */
export class Database {
  readonly invalidations = new InvalidationBus();
  private closed = false;
  private writeQueue: Promise<unknown> = Promise.resolve();

  /**
   * Typed CRUD per table, generated from the schema. A `.synced()` table appears
   * here with `get` only: its write methods do not exist, so the server-truth
   * rule is enforced by the object, not by a runtime check a cast could dodge.
   */
  readonly tables: Record<string, TableApi<Row> | SyncedTableApi<Row>> = {};

  protected constructor(
    readonly schema: Schema,
    protected readonly adapter: SQLiteAdapter,
  ) {}

  /**
   * Opens and migrates a database. Supply the application's row types and the
   * names of its synced tables to get a typed `db.tables`:
   * `Database.open<AppRows, 'c_work_task' | 'c_work_order'>({ ... })`.
   */
  static async open<TRows extends RowMap = RowMap, TSynced extends keyof TRows = never>(
    options: DatabaseOptions,
  ): Promise<Database & { tables: TableApis<TRows, TSynced> }> {
    await options.adapter.open();
    const db = new Database(options.schema, options.adapter);
    await runMigration(options.adapter, options.schema, {
      mode: options.migrate ?? 'auto',
      allowRecreate: options.allowRecreate ?? false,
      ...(options.onMigrationPlan ? { onPlan: options.onMigrationPlan } : {}),
    });
    db.buildTableApis();
    return db as Database & { tables: TableApis<TRows, TSynced> };
  }

  /** Runs a read-only SQL query with positional parameters and returns every matching row, typed `T`. */
  async query<T>(sql: string, params: SqlValue[] = []): Promise<T[]> {
    this.ensureOpen();
    return this.adapter.all<T>(sql, params);
  }

  /** Runs a read-only SQL query and returns its first row, or `undefined` when nothing matches. */
  async queryOne<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    this.ensureOpen();
    return this.adapter.get<T>(sql, params);
  }

  /**
   * Runs one statement that returns no rows. `invalidates` names the tables the
   * statement wrote so live queries on them re-run; leave it out for a statement
   * that writes nothing (a PRAGMA, an ANALYZE). Prefer `db.tables` or a
   * transaction for ordinary writes — they report row keys and scopes, so only
   * the queries that actually care re-run.
   */
  async execute(sql: string, params: SqlValue[] = [], options: { invalidates?: string[] } = {}): Promise<RunResult> {
    this.ensureOpen();
    const result = await this.adapter.run(sql, params);
    const invalidates = options.invalidates ?? [];
    if (invalidates.length > 0) {
      const log = new WriteLog();
      for (const table of invalidates) log.markTable(table);
      this.invalidations.emit(log.toEvent());
    }
    return result;
  }

  /**
   * Runs `work` inside one SQLite transaction. Transactions are serialised —
   * one adapter is one connection — so overlapping callers queue rather than
   * interleave their BEGINs. On success the transaction's write log becomes
   * exactly one invalidation event; on failure everything rolls back and no
   * event is emitted, so a live query can never show a row that was undone.
   */
  async transaction<T>(work: (tx: Transaction) => Promise<T>): Promise<T> {
    this.ensureOpen();
    const run = this.writeQueue.then(() => this.runTransaction(work));
    this.writeQueue = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  private async runTransaction<T>(work: (tx: Transaction) => Promise<T>): Promise<T> {
    const log = new WriteLog();
    const tx = new Transaction(this.adapter, log);
    await this.adapter.exec('BEGIN IMMEDIATE');
    let result: T;
    try {
      result = await work(tx);
      await this.adapter.exec('COMMIT');
    } catch (error) {
      await this.adapter.exec('ROLLBACK');
      throw error;
    }
    if (!log.isEmpty()) this.invalidations.emit(log.toEvent());
    return result;
  }

  /** Closes the underlying adapter. Every method on this instance throws afterwards; safe to call more than once. */
  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    await this.adapter.close();
  }

  /** The declared definition of one table. Throws if the schema does not declare it. */
  tableDef(name: string): TableDef {
    const table = this.schema.tables.find((t) => t.name === name);
    if (!table) throw new Error(`Table ${name} is not in the schema`);
    return table;
  }

  /** The column holding a table's row key: the `.synced()` key, or `system_id`. */
  keyColumn(name: string): string {
    return this.tableDef(name).synced?.key ?? SYSTEM_ID_COLUMN;
  }

  protected ensureOpen(): void {
    if (this.closed) throw new Error('Database is closed');
  }

  private buildTableApis(): void {
    for (const table of this.schema.tables) {
      const keyColumn = table.synced?.key ?? SYSTEM_ID_COLUMN;
      const get = async (key: string): Promise<Row | undefined> =>
        this.queryOne<Row>(`SELECT * FROM ${quoteIdentifier(table.name)} WHERE ${quoteIdentifier(keyColumn)} = ?`, [key]);

      if (table.synced) {
        this.tables[table.name] = { get };
        continue;
      }

      this.tables[table.name] = {
        get,
        insert: async (row: Row) => {
          await this.transaction(async (tx) => writeRow(tx, table, keyColumn, String(row[keyColumn] ?? ''), row, 'insert'));
        },
        update: async (key: string, patch: Partial<Row>) =>
          this.transaction(async (tx) => writeRow(tx, table, keyColumn, key, patch as Row, 'update')),
        upsert: async (row: Row) => {
          await this.transaction(async (tx) => writeRow(tx, table, keyColumn, String(row[keyColumn] ?? ''), row, 'upsert'));
        },
        delete: async (key: string) =>
          this.transaction(async (tx) => {
            const result = await tx.execute(
              `DELETE FROM ${quoteIdentifier(table.name)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
              [key],
            );
            tx.markWritten(table.name, key, null);
            return result.changes;
          }),
      };
    }
  }
}
