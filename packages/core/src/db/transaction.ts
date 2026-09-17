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

  async query<T>(sql: string, params: SqlValue[] = []): Promise<T[]> {
    return this.adapter.all<T>(sql, params);
  }

  async queryOne<T>(sql: string, params: SqlValue[] = []): Promise<T | undefined> {
    return this.adapter.get<T>(sql, params);
  }

  async execute(sql: string, params: SqlValue[] = [], options: { invalidates?: string[] } = {}): Promise<RunResult> {
    const result = await this.adapter.run(sql, params);
    for (const table of options.invalidates ?? []) this.log.markTable(table);
    return result;
  }

  markWritten(table: string, rowKey: string, scope: ScopeValues | null = null): void {
    this.log.markRow(table, rowKey, scope);
  }

  markTableWritten(table: string): void {
    this.log.markTable(table);
  }
}
