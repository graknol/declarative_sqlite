/**
 * Dirty Row Tracking for Synchronization
 * 
 * Tracks which rows have been modified locally and need to be synchronized
 * to other devices/nodes in a distributed system.
 */

import type { SQLiteAdapter } from '../adapters/adapter.interface.js';

export interface DirtyRow {
  tableName: string;
  rowId: string;
  hlc: string; // HLC timestamp
  isFullRow: boolean; // true if full row should be sent, false if only LWW columns
}

export interface DirtyRowStore {
  /**
   * Initialize the store (e.g. create tables)
   */
  init(): Promise<void>;

  /**
   * Mark a row as dirty (needs sync)
   */
  markDirty(row: DirtyRow): Promise<void>;

  /**
   * Get all dirty rows
   */
  getAllDirty(): Promise<DirtyRow[]>;

  /**
   * Get dirty rows for a specific table
   */
  getDirtyForTable(tableName: string): Promise<DirtyRow[]>;

  /**
   * Removes a list of rows from the dirty rows log.
   * 
   * This should be called after successfully syncing rows with a server.
   * It uses a lock-free approach to only remove rows that have not been
   * modified again since the sync started.
   */
  remove(operations: DirtyRow[]): Promise<void>;

  /**
   * Clear a dirty row (after successful sync)
   */
  clearDirty(tableName: string, rowId: string): Promise<void>;

  /**
   * Clear all dirty rows for a table
   */
  clearDirtyForTable(tableName: string): Promise<void>;

  /**
   * Clear all dirty rows
   */
  clearAll(): Promise<void>;
}

/**
 * SQLite-backed implementation of DirtyRowStore
 */
export class SqliteDirtyRowStore implements DirtyRowStore {
  constructor(private adapter: SQLiteAdapter) {}

  async init(): Promise<void> {
    await this.adapter.exec(`
      CREATE TABLE IF NOT EXISTS __dirty_rows (
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        hlc TEXT NOT NULL,
        is_full_row INTEGER NOT NULL,
        PRIMARY KEY (table_name, row_id)
      )
    `);
  }

  async markDirty(row: DirtyRow): Promise<void> {
    const stmt = this.adapter.prepare(`
      INSERT OR REPLACE INTO __dirty_rows (table_name, row_id, hlc, is_full_row)
      VALUES (?, ?, ?, ?)
    `);

    await stmt.run(row.tableName, row.rowId, row.hlc, row.isFullRow ? 1 : 0);
  }

  async getAllDirty(): Promise<DirtyRow[]> {
    const stmt = this.adapter.prepare(`
      SELECT table_name, row_id, hlc, is_full_row
      FROM __dirty_rows
      ORDER BY hlc ASC
    `);

    const rows = await stmt.all<any>();
    return rows.map(row => ({
      tableName: row.table_name,
      rowId: row.row_id,
      hlc: row.hlc,
      isFullRow: row.is_full_row === 1,
    }));
  }

  async getDirtyForTable(tableName: string): Promise<DirtyRow[]> {
    const stmt = this.adapter.prepare(`
      SELECT table_name, row_id, hlc, is_full_row
      FROM __dirty_rows
      WHERE table_name = ?
      ORDER BY hlc ASC
    `);

    const rows = await stmt.all<any>([tableName]);
    return rows.map(row => ({
      tableName: row.table_name,
      rowId: row.row_id,
      hlc: row.hlc,
      isFullRow: row.is_full_row === 1,
    }));
  }

  /**
   * Removes a list of rows from the dirty rows log.
   * 
   * This should be called after successfully syncing rows with a server.
   * It uses a lock-free approach to only remove rows that have not been
   * modified again since the sync started.
   */
  async remove(operations: DirtyRow[]): Promise<void> {
    for (const operation of operations) {
      const stmt = this.adapter.prepare(`
        DELETE FROM __dirty_rows
        WHERE table_name = ? AND row_id = ? AND hlc = ? AND is_full_row = ?
      `);

      await stmt.run(
        operation.tableName,
        operation.rowId,
        operation.hlc,
        operation.isFullRow ? 1 : 0,
      );
    }
  }

  async clearDirty(tableName: string, rowId: string): Promise<void> {
    const stmt = this.adapter.prepare(`
      DELETE FROM __dirty_rows
      WHERE table_name = ? AND row_id = ?
    `);

    await stmt.run(tableName, rowId);
  }

  async clearDirtyForTable(tableName: string): Promise<void> {
    const stmt = this.adapter.prepare(`
      DELETE FROM __dirty_rows
      WHERE table_name = ?
    `);

    await stmt.run(tableName);
  }

  async clearAll(): Promise<void> {
    const stmt = this.adapter.prepare('DELETE FROM __dirty_rows');
    await stmt.run();
  }
}
