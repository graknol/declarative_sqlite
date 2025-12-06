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
  operation: 'insert' | 'update' | 'delete';
  timestamp: string; // HLC timestamp
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

  async markDirty(row: DirtyRow): Promise<void> {
    const stmt = this.adapter.prepare(`
      INSERT OR REPLACE INTO __dirty_rows (table_name, row_id, operation, timestamp)
      VALUES (?, ?, ?, ?)
    `);

    await stmt.run([row.tableName, row.rowId, row.operation, row.timestamp]);
  }

  async getAllDirty(): Promise<DirtyRow[]> {
    const stmt = this.adapter.prepare(`
      SELECT table_name, row_id, operation, timestamp
      FROM __dirty_rows
      ORDER BY timestamp ASC
    `);

    const rows = await stmt.all<any>();
    return rows.map(row => ({
      tableName: row.table_name,
      rowId: row.row_id,
      operation: row.operation,
      timestamp: row.timestamp,
    }));
  }

  async getDirtyForTable(tableName: string): Promise<DirtyRow[]> {
    const stmt = this.adapter.prepare(`
      SELECT table_name, row_id, operation, timestamp
      FROM __dirty_rows
      WHERE table_name = ?
      ORDER BY timestamp ASC
    `);

    const rows = await stmt.all<any>([tableName]);
    return rows.map(row => ({
      tableName: row.table_name,
      rowId: row.row_id,
      operation: row.operation,
      timestamp: row.timestamp,
    }));
  }

  async clearDirty(tableName: string, rowId: string): Promise<void> {
    const stmt = this.adapter.prepare(`
      DELETE FROM __dirty_rows
      WHERE table_name = ? AND row_id = ?
    `);

    await stmt.run([tableName, rowId]);
  }

  async clearDirtyForTable(tableName: string): Promise<void> {
    const stmt = this.adapter.prepare(`
      DELETE FROM __dirty_rows
      WHERE table_name = ?
    `);

    await stmt.run([tableName]);
  }

  async clearAll(): Promise<void> {
    const stmt = this.adapter.prepare('DELETE FROM __dirty_rows');
    await stmt.run([]);
  }
}
