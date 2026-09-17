import type { RunResult, SQLiteAdapter } from '../adapters/adapter';
import type { ScopeValues, SqlValue } from '../types';
import type { WriteLog } from './invalidation-bus';

/**
 * The handle a transaction body works through. It reads and writes like the
 * database does, but every write must say which rows it touched — either by
 * calling `markWritten` with the row key and its scope values, or by declaring
 * the tables it could not be precise about. What is marked here becomes the one
 * invalidation event emitted after the transaction commits.
 */
export class Transaction {
  constructor(
    private readonly adapter: SQLiteAdapter,
    private readonly log: WriteLog,
  ) {}

  /** Runs a read-only SQL query with positional parameters and returns every matching row, typed `T`. Sees this transaction's own uncommitted writes. */
  async query<T>(sql: string, params: SqlValue[] = []): Promise<T[]> {
    return this.adapter.all<T>(sql, params);
  }

  /** Runs a read-only SQL query and returns its first row, or `undefined` when nothing matches. Sees this transaction's own uncommitted writes. */
  async queryOne<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    return this.adapter.get<T>(sql, params);
  }

  /**
   * Runs one statement that returns no rows. `invalidates` names the tables it
   * wrote so live queries on them re-run once the enclosing transaction
   * commits; leave it out for a statement that writes nothing. Prefer
   * `markWritten` for a single row you can name — it lets a live query re-run
   * only for that row's scope instead of the whole table. Raw SQL is not
   * covered by the server-truth guard: writing a `.synced()` table through
   * `execute` outside the pull applier or the outbox committer corrupts the
   * cursor contract.
   */
  async execute(sql: string, params: SqlValue[] = [], options: { invalidates?: string[] } = {}): Promise<RunResult> {
    const result = await this.adapter.run(sql, params);
    for (const table of options.invalidates ?? []) this.log.markTable(table);
    return result;
  }

  /** Records that one row was written, with its scope values (or `null` when the table has no scope, or the scope could not be determined). Folds into the transaction's single invalidation event on commit. */
  markWritten(table: string, rowKey: string, scope: ScopeValues | null = null): void {
    this.log.markRow(table, rowKey, scope);
  }

  /** Records that a table was written in a way that cannot be pinned to individual rows, so every live query on it must re-run after commit. */
  markTableWritten(table: string): void {
    this.log.markTable(table);
  }
}
