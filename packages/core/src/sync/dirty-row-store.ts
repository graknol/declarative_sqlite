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
   * Get a specific dirty row entry
   */
  getDirtyRow(tableName: string, rowId: string): Promise<DirtyRow | null>;

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
 * Note: Table creation is handled by schema migration
 */
export class SqliteDirtyRowStore implements DirtyRowStore {
  constructor(private adapter: SQLiteAdapter) {}

  async markDirty(row: DirtyRow): Promise<void> {
    // HLC timestamps automatically serialize to strings via toString()
    const hlcString = typeof row.hlc === 'string' 
      ? row.hlc 
      : String(row.hlc); // This now works correctly thanks to the toString() method
    
    const stmt = this.adapter.prepare(`
      INSERT OR REPLACE INTO __dirty_rows (table_name, row_id, hlc, is_full_row)
      VALUES (?, ?, ?, ?)
    `);

    await stmt.run(row.tableName, row.rowId, hlcString, row.isFullRow ? 1 : 0);
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

  async getDirtyRow(tableName: string, rowId: string): Promise<DirtyRow | null> {
    const stmt = this.adapter.prepare(`
      SELECT table_name, row_id, hlc, is_full_row
      FROM __dirty_rows
      WHERE table_name = ? AND row_id = ?
    `);

    const row = await stmt.get<any>(tableName, rowId);
    if (!row) return null;

    return {
      tableName: row.table_name,
      rowId: row.row_id,
      hlc: row.hlc,
      isFullRow: row.is_full_row === 1,
    };
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
