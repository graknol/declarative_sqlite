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

// Schema builders
export { SchemaBuilder } from './schema/builders/schema-builder';
export { TableBuilder } from './schema/builders/table-builder';
export { KeyBuilder } from './schema/builders/key-builder';
export {
  TextColumnBuilder,
  IntegerColumnBuilder,
  RealColumnBuilder,
  GuidColumnBuilder,
  DateColumnBuilder,
  FilesetColumnBuilder,
} from './schema/builders/column-builders';

// Migration
export { SchemaMigrator } from './migration/schema-migrator';
export { SchemaIntrospector } from './migration/schema-introspector';
export { SchemaDiffer } from './migration/schema-differ';
export { MigrationGenerator } from './migration/migration-generator';
export type { 
  MigrationPlan,
} from './migration/schema-migrator';
export type {
  SchemaDiff,
  TableAlterations,
  ColumnModification,
} from './migration/schema-differ';
export type {
  MigrationOperation,
} from './migration/migration-generator';

// Version
export const VERSION = '0.1.0';
