import type { ColumnDef, KeyDef, Schema, TableDef } from '../schema/types';

/** A column whose storage type or NOT NULL-ness changed between what is declared and what is live — the two column-level reasons (besides the primary key) this library ever rebuilds a table. */
export interface ColumnRetype {
  from: ColumnDef;
  to: ColumnDef;
}

/**
 * Everything one existing table needs. `requiresRecreate` means ALTER TABLE
 * cannot express it: a storage-type change, a NOT NULL flip in either
 * direction, or a changed primary key. `extraColumns` are the live table's
 * full column definitions for columns the schema no longer declares; a
 * recreate carries them into the rebuilt table unchanged instead of dropping
 * them and their data. `keysToDrop` names live indexes that must be removed
 * because a declared key of the same name has a different type or column
 * list — dropping an index loses no row data, so replacing it this way stays
 * inside the additive rule.
 */
export interface TableAlteration {
  table: string;
  columnsToAdd: ColumnDef[];
  keysToAdd: KeyDef[];
  keysToDrop: string[];
  columnsToRetype: ColumnRetype[];
  extraColumns: ColumnDef[];
  requiresRecreate: boolean;
}

/**
 * The difference between what the application declared and what the database
 * holds. `extraTables` and `extraColumns` exist so the plan can *report* what is
 * in the database and not in the schema; they are never turned into drops.
 */
export interface MigrationDiff {
  tablesToCreate: TableDef[];
  tablesToAlter: TableAlteration[];
  extraTables: string[];
  extraColumns: Array<{ table: string; column: string }>;
  hasChanges: boolean;
}

function samePrimaryKey(declared: TableDef, live: TableDef): boolean {
  const a = declared.keys.find((k) => k.type === 'PRIMARY');
  const b = live.keys.find((k) => k.type === 'PRIMARY');
  if (!a) return true;
  if (!b) return false;
  return a.columns.join(',') === b.columns.join(',');
}

/**
 * Compares the declared schema with an introspected one. Additive only: a table
 * or column that exists solely in the database is reported and left alone, so an
 * app rolling back to an older build never loses data. A storage-type change, a
 * NOT NULL flip in either direction, or a changed primary key marks the table
 * `requiresRecreate`, which the generator refuses to act on unless `allowRecreate`
 * is set. A live key that shares a declared key's name but not its shape (type or
 * column list) is scheduled for replacement rather than treated as already
 * satisfied.
 */
export function diffSchema(declared: Schema, live: Schema): MigrationDiff {
  const liveTables = new Map(live.tables.map((t) => [t.name, t]));
  const declaredNames = new Set(declared.tables.map((t) => t.name));

  const tablesToCreate: TableDef[] = [];
  const tablesToAlter: TableAlteration[] = [];
  const extraColumns: Array<{ table: string; column: string }> = [];

  for (const declaredTable of declared.tables) {
    const liveTable = liveTables.get(declaredTable.name);
    if (!liveTable) {
      tablesToCreate.push(declaredTable);
      continue;
    }

    const liveColumns = new Map(liveTable.columns.map((c) => [c.name, c]));
    const columnsToAdd: ColumnDef[] = [];
    const columnsToRetype: ColumnRetype[] = [];

    for (const column of declaredTable.columns) {
      const liveColumn = liveColumns.get(column.name);
      if (!liveColumn) {
        columnsToAdd.push(column);
      } else if (liveColumn.type !== column.type || liveColumn.notNull !== column.notNull) {
        columnsToRetype.push({ from: liveColumn, to: column });
      }
    }

    const declaredColumnNames = new Set(declaredTable.columns.map((c) => c.name));
    const tableExtraColumns: ColumnDef[] = [];
    for (const liveColumn of liveTable.columns) {
      if (!declaredColumnNames.has(liveColumn.name)) {
        extraColumns.push({ table: declaredTable.name, column: liveColumn.name });
        tableExtraColumns.push(liveColumn);
      }
    }

    const liveKeysByName = new Map(liveTable.keys.filter((k): k is KeyDef & { name: string } => k.name !== undefined).map((k) => [k.name, k]));
    const keysToAdd: KeyDef[] = [];
    const keysToDrop: string[] = [];
    for (const key of declaredTable.keys) {
      if (key.type === 'PRIMARY' || key.name === undefined) continue;
      const liveKey = liveKeysByName.get(key.name);
      if (!liveKey) {
        keysToAdd.push(key);
        continue;
      }
      const sameShape = liveKey.type === key.type && liveKey.columns.join(',') === key.columns.join(',');
      if (!sameShape) {
        // A live key with this name exists but is the wrong kind or covers the
        // wrong columns. Dropping and recreating it loses no row data, only the
        // index structure, so this still honours the additive rule.
        keysToDrop.push(key.name);
        keysToAdd.push(key);
      }
    }

    const requiresRecreate = columnsToRetype.length > 0 || !samePrimaryKey(declaredTable, liveTable);

    if (columnsToAdd.length > 0 || keysToAdd.length > 0 || requiresRecreate) {
      tablesToAlter.push({
        table: declaredTable.name,
        columnsToAdd,
        keysToAdd,
        keysToDrop,
        columnsToRetype,
        extraColumns: tableExtraColumns,
        requiresRecreate,
      });
    }
  }

  const extraTables = live.tables.filter((t) => !declaredNames.has(t.name)).map((t) => t.name);

  return {
    tablesToCreate,
    tablesToAlter,
    extraTables,
    extraColumns,
    hasChanges: tablesToCreate.length > 0 || tablesToAlter.length > 0,
  };
}
