import type { SqlValue } from '../types';

/** The four types SQLite actually stores. What the migration layer compares. */
export type StorageType = 'TEXT' | 'INTEGER' | 'REAL' | 'BLOB';

/** What the declaration meant. `date` and `guid` are stored as TEXT; keeping the intent lets the app and the docs stay honest without confusing the differ. */
export type LogicalType = 'text' | 'integer' | 'real' | 'date' | 'guid' | 'blob';

/** One declared column. `maxLength` is advisory metadata for the app's forms — SQLite does not enforce it and neither does this library. */
export interface ColumnDef {
  name: string;
  type: StorageType;
  logical: LogicalType;
  notNull: boolean;
  defaultValue?: SqlValue;
  maxLength?: number;
}

export type KeyType = 'PRIMARY' | 'UNIQUE' | 'INDEX';

/** A primary key, a unique constraint or a plain index. `name` is generated for indexes when it is not given. */
export interface KeyDef {
  columns: string[];
  type: KeyType;
  name?: string;
}

/** What `.synced()` declares: the column holding the server row key, and the columns a pull may filter on. Both are trusted from the schema; see `validateScopes` for the optional server check. */
export interface SyncedDef {
  key: string;
  scope: string[];
}

/** One table. `library: true` marks the tables this package owns (`outbox`, `sync_cursor`) so the app cannot redeclare them and the server-truth guard can ignore them. */
export interface TableDef {
  name: string;
  columns: ColumnDef[];
  keys: KeyDef[];
  synced?: SyncedDef;
  library: boolean;
}

/** The built, immutable schema: what `Database.open` migrates towards and what every typed API reads its shape from. */
export interface Schema {
  tables: TableDef[];
}

/** Thrown while building or validating a schema. Always names the table or column at fault. */
export class SchemaError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SchemaError';
  }
}
