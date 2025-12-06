import type { SQLiteAdapter } from '../adapters/adapter.interface';
import type { DbTable, DbColumn, DbKey, ColumnType } from '../schema/types';

/**
 * Introspects the live database schema using SQLite system tables
 */
export class SchemaIntrospector {
  constructor(private adapter: SQLiteAdapter) {}

  /**
   * Read all tables from the database
   */
  async getTables(): Promise<DbTable[]> {
    const tables: DbTable[] = [];
    
    // Query sqlite_master for all tables (excluding sqlite internal tables)
    const stmt = this.adapter.prepare(`
      SELECT name FROM sqlite_master 
      WHERE type = 'table' 
        AND name NOT LIKE 'sqlite_%'
      ORDER BY name
    `);
    
    const rows = await stmt.all();
    
    for (const row of rows) {
      const tableName = row.name as string;
      const table = await this.getTableInfo(tableName);
      if (table) {
        tables.push(table);
      }
    }
    
    return tables;
  }

  /**
   * Get detailed information about a specific table
   */
  async getTableInfo(tableName: string): Promise<DbTable | null> {
    try {
      // Get columns using PRAGMA table_info
      const columns = await this.getTableColumns(tableName);
      
      // Get keys/indices
      const keys = await this.getTableKeys(tableName);
      
      return {
        name: tableName,
        columns,
        keys,
        isSystem: tableName.startsWith('__'),
      };
    } catch (error) {
      console.error(`Error getting table info for ${tableName}:`, error);
      return null;
    }
  }

  /**
   * Get columns for a table using PRAGMA table_info
   */
  private async getTableColumns(tableName: string): Promise<DbColumn[]> {
    const stmt = this.adapter.prepare(`PRAGMA table_info(${this.quote(tableName)})`);
    const rows = await stmt.all();
    
    return rows.map((row: any) => {
      const column: DbColumn = {
        name: row.name,
        type: this.mapSQLiteTypeToColumnType(row.type),
        notNull: row.notnull === 1,
        defaultValue: this.parseDefaultValue(row.dflt_value),
      };
      
      // Check if this is an LWW column (companion __hlc column exists)
      const hlcColumnName = `${row.name}__hlc`;
      const hasHlcColumn = rows.some((r: any) => r.name === hlcColumnName);
      if (hasHlcColumn && column.name !== hlcColumnName) {
        column.lww = true;
      }
      
      return column;
    });
  }

  /**
   * Get keys and indices for a table
   */
  private async getTableKeys(tableName: string): Promise<DbKey[]> {
    const keys: DbKey[] = [];
    
    // Get primary key information
    const tableInfoStmt = this.adapter.prepare(`PRAGMA table_info(${this.quote(tableName)})`);
    const tableInfo = await tableInfoStmt.all();
    
    // Find primary key columns
    const pkColumns = tableInfo
      .filter((row: any) => row.pk > 0)
      .sort((a: any, b: any) => a.pk - b.pk)
      .map((row: any) => row.name);
    
    if (pkColumns.length > 0) {
      keys.push({
        columns: pkColumns,
        type: 'PRIMARY',
      });
    }
    
    // Get indices using PRAGMA index_list
    const indexListStmt = this.adapter.prepare(`PRAGMA index_list(${this.quote(tableName)})`);
    const indices = await indexListStmt.all();
    
    for (const index of indices) {
      // Skip auto-generated primary key indices
      if (index.origin === 'pk') continue;
      
      // Get index columns
      const indexInfoStmt = this.adapter.prepare(`PRAGMA index_info(${this.quote(index.name)})`);
      const indexInfo = await indexInfoStmt.all();
      
      const columns = indexInfo
        .sort((a: any, b: any) => a.seqno - b.seqno)
        .map((row: any) => row.name);
      
      keys.push({
        columns,
        type: index.unique ? 'UNIQUE' : 'INDEX',
        name: index.name,
      });
    }
    
    return keys;
  }

  /**
   * Map SQLite type names to our ColumnType enum
   */
  private mapSQLiteTypeToColumnType(sqliteType: string): ColumnType {
    const type = sqliteType.toUpperCase();
    
    if (type.includes('INT')) return 'INTEGER';
    if (type.includes('REAL') || type.includes('FLOAT') || type.includes('DOUBLE')) return 'REAL';
    if (type.includes('TEXT') || type.includes('CHAR') || type.includes('CLOB')) return 'TEXT';
    if (type.includes('BLOB')) return 'TEXT'; // GUID might be stored as BLOB
    
    // Default to TEXT for unknown types
    return 'TEXT';
  }

  /**
   * Parse default value from SQLite
   */
  private parseDefaultValue(dfltValue: any): any {
    if (dfltValue === null || dfltValue === undefined) {
      return undefined;
    }
    
    // Remove quotes if present
    let value = String(dfltValue);
    if ((value.startsWith("'") && value.endsWith("'")) || 
        (value.startsWith('"') && value.endsWith('"'))) {
      value = value.slice(1, -1);
    }
    
    // Try to parse as number
    const num = Number(value);
    if (!isNaN(num) && value !== '') {
      return num;
    }
    
    return value;
  }

  /**
   * Quote identifier for SQLite
   */
  private quote(identifier: string): string {
    return `"${identifier.replace(/"/g, '""')}"`;
  }
}
