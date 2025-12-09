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
  SchemaProvider,
  ValidValue
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

// Database operations
export { DeclarativeDatabase, ConstraintViolationStrategy } from './database/declarative-database';
export { QueryBuilder } from './database/query-builder';
export { SqliteWasmAdapter } from './database/sqlite-wasm-adapter';
export type {
  DatabaseConfig,
  InsertOptions,
  UpdateOptions,
  DeleteOptions,
  QueryOptions,
} from './database/declarative-database';
export type {
  WhereOperator,
  WhereCondition,
  JoinClause,
} from './database/query-builder';

// Synchronization
export { Hlc } from './sync/hlc';
export type { HlcTimestamp } from './sync/hlc';
export { LwwOperations } from './sync/lww-operations';
export type { LwwUpdateOptions } from './sync/lww-operations';
export { SqliteDirtyRowStore } from './sync/dirty-row-store';
export type {
  DirtyRow,
  DirtyRowStore,
} from './sync/dirty-row-store';

// File management
export type { 
  FileMetadata,
  IFileRepository 
} from './files/file-repository.interface';
export { IndexedDBFileRepository } from './files/indexeddb-file-repository';
export { FileSet } from './files/fileset';

// Streaming queries
export { StreamingQuery } from './streaming/streaming-query';
export { QueryStreamManager } from './streaming/query-stream-manager';
export type { QueryOptions as StreamQueryOptions } from './streaming/streaming-query';

// Records
export { DbRecord } from './records/db-record';

// Version
export const VERSION = '0.1.0';
