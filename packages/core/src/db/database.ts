import type { RunResult, SQLiteAdapter } from '../adapters/adapter';
import { runMigration, type MigrationMode, type MigrationPlan } from '../migration/migrate';
import type { Schema } from '../schema/types';
import type { SqlValue } from '../types';
import { InvalidationBus, WriteLog } from './invalidation-bus';

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

  protected constructor(
    readonly schema: Schema,
    protected readonly adapter: SQLiteAdapter,
  ) {}

  /**
   * Opens the adapter and migrates it towards `options.schema` according to
   * `options.migrate` (default `auto`). This is the one entry point every
   * consumer of the library calls; the returned `Database` is ready for reads
   * once the promise resolves, and for writes once later tasks add them.
   */
  static async open(options: DatabaseOptions): Promise<Database> {
    await options.adapter.open();
    const db = new Database(options.schema, options.adapter);
    await runMigration(options.adapter, options.schema, {
      mode: options.migrate ?? 'auto',
      allowRecreate: options.allowRecreate ?? false,
      ...(options.onMigrationPlan ? { onPlan: options.onMigrationPlan } : {}),
    });
    return db;
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

  /** Closes the underlying adapter. Every method on this instance throws afterwards; safe to call more than once. */
  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    await this.adapter.close();
  }

  protected ensureOpen(): void {
    if (this.closed) throw new Error('Database is closed');
  }
}
