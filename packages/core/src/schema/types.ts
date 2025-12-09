/**
 * SQLite column types
 */
export type ColumnType = 'TEXT' | 'INTEGER' | 'REAL' | 'BLOB' | 'GUID' | 'DATE' | 'FILESET';

/**
 * Key type enumeration
 */
export type KeyType = 'PRIMARY' | 'UNIQUE' | 'INDEX';

/**
 * Valid value definition for a column
 */
export interface ValidValue {
  value: any;
  label: string;
}

/**
 * Database column definition
 */
export interface DbColumn {
  name: string;
  type: ColumnType;
  notNull?: boolean;
  defaultValue?: any;
  defaultFn?: () => any;
  lww?: boolean;
  maxLength?: number;
  maxFileCount?: number;
  maxFileSize?: number;
  validValues?: ValidValue[];
}

/**
 * Database key (primary key, unique constraint, or index)
 */
export interface DbKey {
  columns: string[];
  type: KeyType;
  name?: string;
}

/**
 * Database table definition
 */
export interface DbTable {
  name: string;
  columns: DbColumn[];
  keys: DbKey[];
  isSystem: boolean;
}

/**
 * Database view definition
 */
export interface DbView {
  name: string;
  sql: string;
  columns: { name: string; type: ColumnType }[];
}

/**
 * Complete database schema
 */
export interface Schema {
  tables: DbTable[];
  views: DbView[];
  version: string;
}

/**
 * Schema provider interface for context analysis
 */
export interface SchemaProvider {
  tableHasColumn(tableName: string, columnName: string): boolean;
  getTablesWithColumn(columnName: string): string[];
}
