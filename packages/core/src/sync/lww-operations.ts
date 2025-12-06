/**
 * Last-Write-Wins (LWW) Operations
 * 
 * Provides update and query operations with automatic HLC timestamp management
 * for conflict-free distributed synchronization.
 */

import type { SQLiteAdapter } from '../adapters/adapter.interface.js';
import { Hlc, type HlcTimestamp } from './hlc.js';

export interface LwwUpdateOptions {
  where?: string;
  whereArgs?: any[];
}

export class LwwOperations {
  constructor(
    private adapter: SQLiteAdapter,
    private hlc: Hlc
  ) {}

  /**
   * Update LWW columns with automatic HLC timestamp management
   * 
   * @param tableName - Name of the table
   * @param values - Column values to update (LWW columns only)
   * @param options - WHERE clause options
   */
  async updateLww(
    tableName: string,
    values: Record<string, any>,
    options?: LwwUpdateOptions
  ): Promise<void> {
    if (Object.keys(values).length === 0) {
      return;
    }

    const timestamp = this.hlc.now();
    const timestampStr = Hlc.toString(timestamp);

    // Build SET clause for both value and __hlc columns
    const setClauses: string[] = [];
    const setValues: any[] = [];

    for (const [column, value] of Object.entries(values)) {
      setClauses.push(`"${column}" = ?`);
      setClauses.push(`"${column}__hlc" = ?`);
      setValues.push(value, timestampStr);
    }

    // Build WHERE clause
    const whereClause = options?.where ? `WHERE ${options.where}` : '';
    const whereArgs = options?.whereArgs || [];

    const sql = `
      UPDATE "${tableName}"
      SET ${setClauses.join(', ')}
      ${whereClause}
    `;

    const stmt = this.adapter.prepare(sql);
    await stmt.run([...setValues, ...whereArgs]);
  }

  /**
   * Conditionally update LWW column if incoming timestamp is newer
   * Used during synchronization to apply remote changes
   * 
   * @param tableName - Name of the table
   * @param rowId - ID of the row to update
   * @param column - LWW column name
   * @param value - New value
   * @param incomingTimestamp - HLC timestamp from remote
   * @returns true if update was applied, false if local was newer
   */
  async updateLwwIfNewer(
    tableName: string,
    rowId: string,
    column: string,
    value: any,
    incomingTimestamp: HlcTimestamp
  ): Promise<boolean> {
    // Get current HLC timestamp for this column
    const stmt = this.adapter.prepare(`
      SELECT "${column}__hlc" as hlc
      FROM "${tableName}"
      WHERE system_id = ?
    `);

    const row = await stmt.get<any>([rowId]);
    
    if (!row || !row.hlc) {
      // No existing timestamp, apply update
      await this.updateLww(tableName, { [column]: value }, {
        where: 'system_id = ?',
        whereArgs: [rowId],
      });
      return true;
    }

    const currentTimestamp = Hlc.parse(row.hlc);

    // Only update if incoming is newer
    if (Hlc.isAfter(incomingTimestamp, currentTimestamp)) {
      const timestampStr = Hlc.toString(incomingTimestamp);
      
      const updateStmt = this.adapter.prepare(`
        UPDATE "${tableName}"
        SET "${column}" = ?, "${column}__hlc" = ?
        WHERE system_id = ?
      `);
      
      await updateStmt.run([value, timestampStr, rowId]);
      return true;
    }

    return false;
  }

  /**
   * Get LWW column values with their timestamps
   * 
   * @param tableName - Name of the table
   * @param rowId - ID of the row
   * @param columns - LWW column names to retrieve
   */
  async getLwwValues(
    tableName: string,
    rowId: string,
    columns: string[]
  ): Promise<Record<string, { value: any; timestamp: HlcTimestamp }>> {
    const selectClauses = columns.flatMap(col => [`"${col}"`, `"${col}__hlc"`]);
    
    const stmt = this.adapter.prepare(`
      SELECT ${selectClauses.join(', ')}
      FROM "${tableName}"
      WHERE system_id = ?
    `);

    const row = await stmt.get<any>([rowId]);
    
    if (!row) {
      throw new Error(`Row not found: ${tableName}[${rowId}]`);
    }

    const result: Record<string, { value: any; timestamp: HlcTimestamp }> = {};

    for (const column of columns) {
      const hlcStr = row[`${column}__hlc`];
      result[column] = {
        value: row[column],
        timestamp: hlcStr ? Hlc.parse(hlcStr) : { milliseconds: 0, counter: 0, nodeId: '' },
      };
    }

    return result;
  }

  /**
   * Merge LWW values from multiple sources
   * Returns the value with the latest timestamp for each column
   * 
   * @param values - Array of LWW values from different sources
   */
  static mergeLwwValues(
    values: Array<Record<string, { value: any; timestamp: HlcTimestamp }>>
  ): Record<string, { value: any; timestamp: HlcTimestamp }> {
    if (values.length === 0) {
      return {};
    }

    const merged: Record<string, { value: any; timestamp: HlcTimestamp }> = {};

    // Get all column names
    const allColumns = new Set<string>();
    for (const valueSet of values) {
      for (const column of Object.keys(valueSet)) {
        allColumns.add(column);
      }
    }

    // For each column, find the value with the latest timestamp
    for (const column of allColumns) {
      let latest: { value: any; timestamp: HlcTimestamp } | null = null;

      for (const valueSet of values) {
        if (valueSet[column]) {
          if (!latest || Hlc.isAfter(valueSet[column].timestamp, latest.timestamp)) {
            latest = valueSet[column];
          }
        }
      }

      if (latest) {
        merged[column] = latest;
      }
    }

    return merged;
  }
}
