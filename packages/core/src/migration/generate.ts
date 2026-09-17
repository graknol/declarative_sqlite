import { quoteIdentifier } from '../db/sql';
import type { ColumnDef, KeyDef, Schema, TableDef } from '../schema/types';
import type { MigrationDiff, TableAlteration } from './diff';

/** One step of a migration: a human-readable description and the statements that carry it out, in order. */
export interface MigrationOperation {
  description: string;
  sql: string[];
}

/**
 * Thrown when the schema cannot be reached without rebuilding a table and
 * `allowRecreate` was not set, or when a recreate would have to guess at a
 * live column it cannot safely reproduce. Lists every table that would have
 * to be rebuilt. `message` defaults to the ordinary "needs allowRecreate"
 * explanation but can be overridden for a more specific refusal.
 */
export class MigrationBlockedError extends Error {
  constructor(
    public readonly tables: string[],
    message?: string,
  ) {
    super(
      message ??
        `Migration needs to recreate ${tables.join(', ')} (a column type or the primary key changed). ` +
          `Open the database with allowRecreate: true to let it, after confirming the data can be copied.`,
    );
    this.name = 'MigrationBlockedError';
  }
}

function literal(value: string | number | null | Uint8Array): string {
  if (typeof value === 'number') return String(value);
  if (value === null) return 'NULL';
  if (value instanceof Uint8Array) {
    const hex = Array.from(value)
      .map((byte) => byte.toString(16).padStart(2, '0'))
      .join('')
      .toUpperCase();
    return `X'${hex}'`;
  }
  return `'${value.replace(/'/g, "''")}'`;
}

function columnSql(column: ColumnDef): string {
  let sql = `${quoteIdentifier(column.name)} ${column.type}`;
  if (column.notNull) {
    sql += ' NOT NULL';
    if (column.defaultValue !== undefined) sql += ` DEFAULT ${literal(column.defaultValue)}`;
  } else if (column.defaultValue !== undefined) {
    sql += ` DEFAULT ${literal(column.defaultValue)}`;
  }
  return sql;
}

/**
 * Renders the `CREATE INDEX` statement for one key, using `UNIQUE INDEX` when
 * the key's `type` is `UNIQUE` so the constraint is actually enforced. The
 * kind always comes from `key.type`, never guessed from the generated name
 * (`uq_…` / `idx_…`), since an app can name its own indexes however it likes.
 */
function createIndexSql(key: KeyDef, tableName: string): string {
  const keyword = key.type === 'UNIQUE' ? 'UNIQUE INDEX' : 'INDEX';
  return `CREATE ${keyword} IF NOT EXISTS ${quoteIdentifier(key.name as string)} ON ${quoteIdentifier(tableName)} (${key.columns.map(quoteIdentifier).join(', ')})`;
}

/** Renders `CREATE TABLE` plus the table's indexes. `tableName` overrides the name, which the recreation flow uses for its temporary table. */
export function createTableSql(table: TableDef, tableName = table.name): string[] {
  const parts = table.columns.map(columnSql);
  for (const key of table.keys) {
    if (key.type === 'PRIMARY') parts.push(`PRIMARY KEY (${key.columns.map(quoteIdentifier).join(', ')})`);
    else if (key.type === 'UNIQUE') parts.push(`UNIQUE (${key.columns.map(quoteIdentifier).join(', ')})`);
  }
  const sql = [`CREATE TABLE ${quoteIdentifier(tableName)} (\n  ${parts.join(',\n  ')}\n)`];
  if (tableName === table.name) {
    for (const key of table.keys) {
      if (key.type !== 'INDEX' || !key.name) continue;
      sql.push(createIndexSql(key, table.name));
    }
  }
  return sql;
}

/**
 * Builds the temp-table recreate for one table: `CREATE TABLE ... __migrate_new`,
 * an `INSERT ... SELECT` that copies every surviving column, `DROP TABLE` and a
 * rename back to the original name. Two kinds of columns survive a recreate that
 * are not in `declared.columns` minus `columnsToAdd`: `alteration.extraColumns`
 * (live columns the schema no longer declares — carried through unchanged so a
 * table rebuilt for an unrelated reason never drops data the schema simply
 * stopped mentioning) and columns flipping from nullable to NOT NULL, whose
 * existing NULLs are backfilled with the declared default via `COALESCE` during
 * the copy. Throws `MigrationBlockedError` rather than guessing when a live
 * extra column is NOT NULL with no reconstructable default.
 */
function recreateSql(alteration: TableAlteration, declared: TableDef): MigrationOperation {
  const temp = `${declared.name}__migrate_new`;
  const addedNames = new Set(alteration.columnsToAdd.map((column) => column.name));
  const declaredCarried = declared.columns.filter((column) => !addedNames.has(column.name));
  const extra = alteration.extraColumns;

  const unreconstructable = extra.filter((column) => column.notNull && column.defaultValue === undefined);
  if (unreconstructable.length > 0) {
    throw new MigrationBlockedError(
      [declared.name],
      `Cannot recreate "${declared.name}": the live column(s) ${unreconstructable
        .map((column) => column.name)
        .join(', ')} are NOT NULL with no default this library can safely reproduce (likely a non-literal SQL ` +
        `default). Refusing rather than guessing at a value and risking a constraint violation or silent data loss.`,
    );
  }

  const retypeByName = new Map(alteration.columnsToRetype.map((retype) => [retype.to.name, retype]));
  const carried = [...declaredCarried, ...extra];

  const tempTable: TableDef = { ...declared, columns: [...declared.columns, ...extra] };
  const sql = [...createTableSql(tempTable, temp)];

  if (carried.length > 0) {
    const insertNames = carried.map((column) => quoteIdentifier(column.name));
    const selectExprs = carried.map((column) => {
      const retype = retypeByName.get(column.name);
      // A column flipping from nullable to NOT NULL needs its existing NULLs
      // backfilled with the declared default — that default is exactly what
      // `notNull()` requires the schema builder to supply for this reason.
      if (retype && retype.to.notNull && !retype.from.notNull && retype.to.defaultValue !== undefined) {
        return `COALESCE(${quoteIdentifier(column.name)}, ${literal(retype.to.defaultValue)})`;
      }
      return quoteIdentifier(column.name);
    });
    sql.push(
      `INSERT INTO ${quoteIdentifier(temp)} (${insertNames.join(', ')}) SELECT ${selectExprs.join(', ')} FROM ${quoteIdentifier(declared.name)}`,
    );
  }
  // Else: nothing overlaps between the old and new shape (every declared column
  // is new and the live table had no columns beyond it) — there is nothing to
  // copy, so the INSERT is skipped entirely rather than emitting
  // "INSERT INTO x () SELECT () FROM y", which SQLite rejects as invalid SQL.

  sql.push(`DROP TABLE ${quoteIdentifier(declared.name)}`, `ALTER TABLE ${quoteIdentifier(temp)} RENAME TO ${quoteIdentifier(declared.name)}`);
  for (const key of declared.keys) {
    if (key.type !== 'INDEX' || !key.name) continue;
    sql.push(createIndexSql(key, declared.name));
  }
  return { description: `Recreate table ${declared.name}`, sql };
}

/**
 * Turns a diff into ordered statements, table by table in the order
 * `diff.tablesToAlter` lists them: a table needing a recreate is rebuilt whole;
 * otherwise its column additions are emitted, then any mismatched keys are
 * dropped and recreated. New tables are always created last, so an index on a
 * new table can never run before the table exists. Throws `MigrationBlockedError`
 * rather than silently rebuilding a table the caller did not agree to rebuild.
 */
export function generateMigration(
  diff: MigrationDiff,
  declared: Schema,
  options: { allowRecreate: boolean },
): MigrationOperation[] {
  const blocked = diff.tablesToAlter.filter((a) => a.requiresRecreate).map((a) => a.table);
  if (blocked.length > 0 && !options.allowRecreate) throw new MigrationBlockedError(blocked);

  const byName = new Map(declared.tables.map((t) => [t.name, t]));
  const operations: MigrationOperation[] = [];

  for (const alteration of diff.tablesToAlter) {
    const table = byName.get(alteration.table);
    if (!table) continue;
    if (alteration.requiresRecreate) {
      operations.push(recreateSql(alteration, table));
      continue;
    }
    for (const column of alteration.columnsToAdd) {
      operations.push({
        description: `Add column ${alteration.table}.${column.name}`,
        sql: [`ALTER TABLE ${quoteIdentifier(alteration.table)} ADD COLUMN ${columnSql(column)}`],
      });
    }
    for (const keyName of alteration.keysToDrop) {
      // Dropping an index loses no row data, only the index structure, so this
      // is safe ahead of the matching create below.
      operations.push({
        description: `Drop index ${keyName}`,
        sql: [`DROP INDEX IF EXISTS ${quoteIdentifier(keyName)}`],
      });
    }
    for (const key of alteration.keysToAdd) {
      if (!key.name) continue;
      operations.push({
        description: `Create index ${key.name}`,
        sql: [createIndexSql(key, alteration.table)],
      });
    }
  }

  for (const table of diff.tablesToCreate) {
    operations.push({ description: `Create table ${table.name}`, sql: createTableSql(table) });
  }

  return operations;
}
