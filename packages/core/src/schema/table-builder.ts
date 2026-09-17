import { ColumnBuilder } from './column-builder';
import { SchemaError, type ColumnDef, type KeyDef, type KeyType, type SyncedDef, type TableDef } from './types';

/** The row key every table carries: the server's `SYSTEM_ID` GUID, lowercase locally. */
export const SYSTEM_ID_COLUMN = 'system_id';
/** The server cursor stamped on every synced row by the IFS `SYNC_SEQ` sequence. */
export const SYNC_SEQ_COLUMN = 'sync_seq';
/** The tombstone flag; 1 means the server says the row is gone. */
export const SYSTEM_REMOVED_COLUMN = 'system_removed';

/**
 * Declares what a set of columns means: the primary key, a unique constraint or a plain index.
 * Returned by `t.key(...)` and used for its side effect. Call `.primary()`, `.unique()`, or
 * `.index()` to set the key type; all are chainable and one call sticks. Default is `.index()`.
 */
export class KeyBuilder {
  private _type: KeyType = 'INDEX';
  private _name: string | undefined;

  constructor(private readonly columns: string[]) {}

  /**
   * Marks this key as the primary key. No name can be given for primary keys;
   * calling `.unique()` or `.index()` afterwards changes the type.
   */
  primary(): void {
    this._type = 'PRIMARY';
  }

  /**
   * Marks this key as a unique constraint with an optional name.
   * If no name is given, unique constraints are unnamed (unlike indexes).
   */
  unique(name?: string): void {
    this._type = 'UNIQUE';
    this._name = name;
  }

  /**
   * Marks this key as a plain index with an optional name.
   * If no name is given, one is auto-generated from the table name and column names.
   */
  index(name?: string): void {
    this._type = 'INDEX';
    this._name = name;
  }

  build(tableName: string): KeyDef {
    if (this._type === 'PRIMARY') return { columns: this.columns, type: 'PRIMARY' };
    // A unique constraint gets a `uq_` name, a plain index `idx_`. The migration
    // layer decides what to emit from `type`, never from the name, but a name that
    // says what it is keeps the generated SQL and any hand inspection honest.
    const prefix = this._type === 'UNIQUE' ? 'uq' : 'idx';
    const name = this._name ?? `${prefix}_${tableName}_${this.columns.join('_')}`;
    return { columns: this.columns, type: this._type, name };
  }
}

/**
 * Declares one table. The builder owns the system columns: `system_id` and
 * `system_removed` on every table, plus `sync_seq` on a `.synced()` one, each
 * added only when the application did not declare it itself — the app's own
 * declaration always wins, so an existing `schema.ts` needs no edit. A synced
 * table with no declared primary key gets one on its sync key.
 */
export class TableBuilder {
  private readonly columns: ColumnBuilder[] = [];
  private readonly columnNames = new Set<string>();
  private readonly keys: KeyBuilder[] = [];
  private synced: SyncedDef | undefined;
  private library = false;

  constructor(public readonly name: string) {}

  /**
   * Declares one text column. Returns a builder for chaining modifiers like `.notNull()` and `.maxLength()`.
   */
  text(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'TEXT', 'text'), name);
  }

  /**
   * Declares one integer column. Returns a builder for chaining modifiers like `.notNull()`.
   */
  integer(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'INTEGER', 'integer'), name);
  }

  /**
   * Declares one real (floating-point) column. Returns a builder for chaining modifiers like `.notNull()`.
   */
  real(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'REAL', 'real'), name);
  }

  /**
   * Declares one date column (stored as TEXT, logical type `date`).
   * Returns a builder for chaining modifiers like `.notNull()`.
   */
  date(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'TEXT', 'date'), name);
  }

  /**
   * Declares one GUID column (stored as TEXT, logical type `guid`).
   * Returns a builder for chaining modifiers like `.notNull()`.
   */
  guid(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'TEXT', 'guid'), name);
  }

  /**
   * Declares one blob column. Returns a builder for chaining modifiers like `.notNull()`.
   */
  blob(name: string): ColumnBuilder {
    return this.add(new ColumnBuilder(name, 'BLOB', 'blob'), name);
  }

  /**
   * Declares a constraint on one or more columns: primary key, unique or index.
   * Returns a builder for chaining `.primary()`, `.unique()`, or `.index()`.
   */
  key(...columns: string[]): KeyBuilder {
    const builder = new KeyBuilder(columns);
    this.keys.push(builder);
    return builder;
  }

  /**
   * Marks this table as a synced table and defines its key and scope columns.
   * The key and scope columns must be declared by the builder before `.build()`.
   */
  markSynced(def: SyncedDef): void {
    this.synced = def;
  }

  /**
   * Marks this table as a library table owned by this package (e.g., `outbox`, `sync_cursor`).
   * Library tables do not get system columns and the server-truth validation skips them.
   */
  markLibrary(): void {
    this.library = true;
  }

  /**
   * Returns the immutable `TableDef` for this table, adding system columns as needed,
   * auto-generating primary keys for synced tables, and validating scope columns exist.
   */
  build(): TableDef {
    const columns: ColumnDef[] = [];
    if (!this.library) {
      if (!this.columnNames.has(SYSTEM_ID_COLUMN)) {
        columns.push({ name: SYSTEM_ID_COLUMN, type: 'TEXT', logical: 'guid', notNull: true, defaultValue: '' });
      }
      if (!this.columnNames.has(SYSTEM_REMOVED_COLUMN)) {
        columns.push({ name: SYSTEM_REMOVED_COLUMN, type: 'INTEGER', logical: 'integer', notNull: true, defaultValue: 0 });
      }
      if (this.synced && !this.columnNames.has(SYNC_SEQ_COLUMN)) {
        columns.push({ name: SYNC_SEQ_COLUMN, type: 'INTEGER', logical: 'integer', notNull: true, defaultValue: 0 });
      }
    }
    columns.push(...this.columns.map((c) => c.build()));

    const keys = this.keys.map((k) => k.build(this.name));
    if (!keys.some((k) => k.type === 'PRIMARY')) {
      const keyColumn = this.synced?.key ?? SYSTEM_ID_COLUMN;
      if (columns.some((c) => c.name === keyColumn)) {
        keys.unshift({ columns: [keyColumn], type: 'PRIMARY' });
      }
    }

    if (this.synced) {
      const present = new Set(columns.map((c) => c.name));
      if (!present.has(this.synced.key)) {
        throw new SchemaError(`Table ${this.name}: synced key column "${this.synced.key}" is not declared`);
      }
      for (const scopeColumn of this.synced.scope) {
        if (!present.has(scopeColumn)) {
          throw new SchemaError(`Table ${this.name}: synced scope column "${scopeColumn}" is not declared`);
        }
      }
    }

    const table: TableDef = { name: this.name, columns, keys, library: this.library };
    if (this.synced) table.synced = this.synced;
    return table;
  }

  private add(builder: ColumnBuilder, name: string): ColumnBuilder {
    if (this.columnNames.has(name)) {
      throw new SchemaError(`Table ${this.name}: column "${name}" is declared twice`);
    }
    this.columnNames.add(name);
    this.columns.push(builder);
    return builder;
  }
}
