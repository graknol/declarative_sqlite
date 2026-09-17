import type { ScopeValues, SqlValue } from '../types';
import type { TableDef } from '../schema/types';
import type { Transaction } from './transaction';
import { quoteIdentifier } from './sql';

/** The application's row types, keyed by table name. Supplied as a type argument to `Database.open`; the library never infers row shapes from the fluent builder. */
export type RowMap = Record<string, Record<string, unknown>>;

/** Typed CRUD for a table the application owns. Reads beyond `get` are SQL strings through `db.query`. */
export interface TableApi<TRow> {
  get(key: string): Promise<TRow | undefined>;
  insert(row: TRow): Promise<void>;
  update(key: string, patch: Partial<TRow>): Promise<number>;
  upsert(row: TRow): Promise<void>;
  delete(key: string): Promise<number>;
}

/** What a `.synced()` table exposes: reads only. Its writes belong to the pull applier and the outbox committer. */
export interface SyncedTableApi<TRow> {
  get(key: string): Promise<TRow | undefined>;
}

/** `db.tables` as the application sees it: synced tables read-only, everything else full CRUD. */
export type TableApis<TRows extends RowMap, TSynced extends keyof TRows> = {
  [K in keyof TRows]: K extends TSynced ? SyncedTableApi<TRows[K]> : TableApi<TRows[K]>;
};

/** Coerces a JavaScript value to something SQLite can bind: booleans become 1/0, `undefined` becomes null. */
export function toSqlValue(value: unknown): SqlValue {
  if (value === undefined || value === null) return null;
  if (typeof value === 'boolean') return value ? 1 : 0;
  if (typeof value === 'number' || typeof value === 'string') return value;
  if (value instanceof Uint8Array) return value;
  return String(value);
}

/** Reads a row's scope values out of the values being written, or returns null when the table has no scope. */
export function rowScope(table: TableDef, values: Record<string, unknown>): ScopeValues | null {
  const scopeColumns = table.synced?.scope ?? [];
  if (scopeColumns.length === 0) return null;
  const scope: ScopeValues = {};
  for (const column of scopeColumns) {
    const value = values[column];
    if (value === undefined || value === null) return null;
    scope[column] = typeof value === 'number' ? value : String(value);
  }
  return scope;
}

/** Builds the `INSERT ... ON CONFLICT DO UPDATE` statement used by both `upsert` and the server writer. */
export function upsertSql(table: TableDef, columns: string[], keyColumn: string): string {
  const names = columns.map(quoteIdentifier).join(', ');
  const placeholders = columns.map(() => '?').join(', ');
  const assignments = columns
    .filter((c) => c !== keyColumn)
    .map((c) => `${quoteIdentifier(c)} = excluded.${quoteIdentifier(c)}`)
    .join(', ');
  const update = assignments.length > 0 ? `DO UPDATE SET ${assignments}` : 'DO NOTHING';
  return `INSERT INTO ${quoteIdentifier(table.name)} (${names}) VALUES (${placeholders}) ON CONFLICT(${quoteIdentifier(keyColumn)}) ${update}`;
}

/** Writes one row's columns inside an open transaction and marks it on the write log. Shared by `db.tables` and the server writer. */
export async function writeRow(
  tx: Transaction,
  table: TableDef,
  keyColumn: string,
  key: string,
  values: Record<string, unknown>,
  mode: 'insert' | 'upsert' | 'update',
): Promise<number> {
  const payload: Record<string, unknown> = { ...values, [keyColumn]: key };
  const columns = Object.keys(payload).filter((c) => table.columns.some((col) => col.name === c));
  const params = columns.map((c) => toSqlValue(payload[c]));

  let changes: number;
  if (mode === 'update') {
    const assignments = columns.filter((c) => c !== keyColumn);
    if (assignments.length === 0) return 0;
    const sql = `UPDATE ${quoteIdentifier(table.name)} SET ${assignments.map((c) => `${quoteIdentifier(c)} = ?`).join(', ')} WHERE ${quoteIdentifier(keyColumn)} = ?`;
    const result = await tx.execute(sql, [...assignments.map((c) => toSqlValue(payload[c])), key]);
    changes = result.changes;
  } else if (mode === 'insert') {
    const sql = `INSERT INTO ${quoteIdentifier(table.name)} (${columns.map(quoteIdentifier).join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`;
    const result = await tx.execute(sql, params);
    changes = result.changes;
  } else {
    const result = await tx.execute(upsertSql(table, columns, keyColumn), params);
    changes = result.changes;
  }

  let scope = rowScope(table, payload);
  if (scope === null && (table.synced?.scope.length ?? 0) > 0) {
    const scopeColumns = table.synced?.scope ?? [];
    const existing = await tx.queryOne<Record<string, SqlValue>>(
      `SELECT ${scopeColumns.map(quoteIdentifier).join(', ')} FROM ${quoteIdentifier(table.name)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
      [key],
    );
    if (existing) scope = rowScope(table, existing);
  }
  tx.markWritten(table.name, key, scope);
  return changes;
}
