/**
 * @declarative-sqlite/core
 * 
 * TypeScript port of declarative_sqlite for PWA and Capacitor applications
 * 
 * @packageDocumentation
 */

// Adapters
export type { 
  SQLiteAdapter, 
  PreparedStatement, 
  RunResult 
} from './adapters/adapter.interface';

// Schema types
export type {
  ColumnType,
  KeyType,
  DbColumn,
  DbKey,
  DbTable,
  DbView,
  Schema,
  SchemaProvider
} from './schema/types';

// Version
export const VERSION = '0.1.0';
