import type { Database } from '../db/database';
import { quoteIdentifier } from '../db/sql';
import { SYNC_CURSOR_TABLE } from '../schema/library-tables';
import { formatScope, parseScope, scopeKey } from '../schema/scopes';
import type { ScopeValues } from '../types';

/** One stored cursor: the high-water `SYNC_SEQ` this device has pulled for one `(table, scope)`. */
export interface CursorRow {
  scopeKey: string;
  table: string;
  scope?: ScopeValues;
  lastSyncSeq: number;
  syncedAt: string;
}

/**
 * Remembers how far this device has pulled each `(table, scope)`. A cursor is a
 * high-water mark and only ever moves forward, so a page that arrives out of
 * order cannot rewind it; the rewind that catches rows behind the cursor is the
 * pull service's window rule, not a cursor edit.
 */
export class CursorStore {
  /**
   * Initializes the cursor store with a database connection. Accepts an optional
   * clock function for timestamping cursor updates; the clock is called by `set()` to
   * populate `syncedAt` and defaults to the wall clock if not provided. Useful for
   * testing to ensure deterministic sync timestamps.
   */
  constructor(
    private readonly db: Database,
    private readonly options: { clock?: () => Date } = {},
  ) {}

  /**
   * Retrieves the last sync sequence number for a table and optional scope.
   * Returns zero if no cursor has been recorded yet for this table and scope.
   */
  async get(table: string, scope?: ScopeValues): Promise<number> {
    const row = await this.db.queryOne<{ last_sync_seq: number }>(
      `SELECT last_sync_seq FROM ${quoteIdentifier(SYNC_CURSOR_TABLE)} WHERE scope_key = ?`,
      [scopeKey(table, scope)],
    );
    return row?.last_sync_seq ?? 0;
  }

  /**
   * Updates the cursor for a table and optional scope with the given sequence number.
   * Timestamps the update with the provided clock (or wall clock if not provided).
   * The cursor never moves backwards: if a lower sequence arrives, the higher one is kept.
   * An unscoped cursor (scope undefined) is stored separately from scoped cursors,
   * so they cannot overwrite each other even if they refer to the same table.
   */
  async set(table: string, scope: ScopeValues | undefined, seq: number): Promise<void> {
    const key = scopeKey(table, scope);
    const syncedAt = (this.options.clock?.() ?? new Date()).toISOString();
    await this.db.transaction(async (tx) => {
      await tx.execute(
        `INSERT INTO ${quoteIdentifier(SYNC_CURSOR_TABLE)} (scope_key, table_name, scope, last_sync_seq, synced_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(scope_key) DO UPDATE SET
           last_sync_seq = MAX(excluded.last_sync_seq, ${quoteIdentifier(SYNC_CURSOR_TABLE)}.last_sync_seq),
           synced_at = excluded.synced_at`,
        [key, table, formatScope(scope) ?? null, seq, syncedAt],
      );
      tx.markTableWritten(SYNC_CURSOR_TABLE);
    });
  }

  /**
   * Returns all stored cursors, one row per `(table, scope)` pair that has been synced.
   * Each row includes the table name, optional scope values, the last sequence number,
   * and the ISO timestamp of the last sync.
   */
  async all(): Promise<CursorRow[]> {
    const rows = await this.db.query<{ scope_key: string; table_name: string; scope: string | null; last_sync_seq: number; synced_at: string }>(
      `SELECT scope_key, table_name, scope, last_sync_seq, synced_at FROM ${quoteIdentifier(SYNC_CURSOR_TABLE)} ORDER BY scope_key`,
    );
    return rows.map((row) => ({
      scopeKey: row.scope_key,
      table: row.table_name,
      ...(row.scope ? { scope: parseScope(row.scope) } : {}),
      lastSyncSeq: row.last_sync_seq,
      syncedAt: row.synced_at,
    }));
  }

  /**
   * Returns all cursors for a specific table, including both unscoped and scoped cursors.
   * This filters the result of `all()` to the rows matching the given table name.
   */
  async forTable(table: string): Promise<CursorRow[]> {
    return (await this.all()).filter((row) => row.table === table);
  }

  /** Forgets a cursor so the next pull reads the scope whole. The manual refresh path uses `from: 0` instead and leaves the cursor alone. */
  async reset(table: string, scope?: ScopeValues): Promise<void> {
    await this.db.transaction(async (tx) => {
      await tx.execute(`DELETE FROM ${quoteIdentifier(SYNC_CURSOR_TABLE)} WHERE scope_key = ?`, [scopeKey(table, scope)]);
      tx.markTableWritten(SYNC_CURSOR_TABLE);
    });
  }
}
