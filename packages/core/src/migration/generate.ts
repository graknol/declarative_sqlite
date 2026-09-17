import { quoteIdentifier } from '../db/sql';
import type { ColumnDef, KeyDef, Schema, TableDef } from '../schema/types';
import type { MigrationDiff, TableAlteration } from './diff';

/** One step of a migration: a human-readable description and the statements that carry it out, in order. */
export interface MigrationOperation {
  description: string;
  sql: string[];
}

/** Thrown when the schema cannot be reached without rebuilding a table and `allowRecreate` was not set. Lists every table that would have to be rebuilt. */
export class MigrationBlockedError extends Error {
  constructor(public readonly tables: string[]) {
    super(
      `Migration needs to recreate ${tables.join(', ')} (a column type or the primary key changed). ` +
        `Open the database with allowRecreate: true to let it, after confirming the data can be copied.`,
    );
    this.name = 'MigrationBlockedError';
  }
}

function literal(value: string | number | null | Uint8Array): string {
  if (typeof value === 'number') return String(value);
  if (value === null) return 'NULL';
  if (value instanceof Uint8Array) throw new Error('A BLOB cannot be a column default');
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

function recreateSql(alteration: TableAlteration, declared: TableDef): MigrationOperation {
  const temp = `${declared.name}__migrate_new`;
  const carried = declared.columns
    .filter((column) => !alteration.columnsToAdd.some((added) => added.name === column.name))
    .map((column) => quoteIdentifier(column.name));

  const sql = [
    ...createTableSql(declared, temp),
    `INSERT INTO ${quoteIdentifier(temp)} (${carried.join(', ')}) SELECT ${carried.join(', ')} FROM ${quoteIdentifier(declared.name)}`,
    `DROP TABLE ${quoteIdentifier(declared.name)}`,
    `ALTER TABLE ${quoteIdentifier(temp)} RENAME TO ${quoteIdentifier(declared.name)}`,
  ];
  for (const key of declared.keys) {
    if (key.type !== 'INDEX' || !key.name) continue;
    sql.push(createIndexSql(key, declared.name));
  }
  return { description: `Recreate table ${declared.name}`, sql };
}

/**
 * Turns a diff into ordered statements: recreations first, then column and index
 * additions, then new tables, so an index on a new table cannot run before the
 * table exists. Throws `MigrationBlockedError` rather than silently rebuilding a
 * table the caller did not agree to rebuild.
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
