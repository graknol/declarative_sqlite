import type { ColumnDef, KeyDef, Schema, TableDef } from '../schema/types';

/** A column whose storage type changed. The only reason this library ever rebuilds a table. */
export interface ColumnRetype {
  from: ColumnDef;
  to: ColumnDef;
}

/** Everything one existing table needs. `requiresRecreate` means ALTER TABLE cannot express it. */
export interface TableAlteration {
  table: string;
  columnsToAdd: ColumnDef[];
  keysToAdd: KeyDef[];
  columnsToRetype: ColumnRetype[];
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
 * app rolling back to an older build never loses data. A storage-type change or
 * a changed primary key marks the table `requiresRecreate`, which the generator
 * refuses to act on unless `allowRecreate` is set.
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
      } else if (liveColumn.type !== column.type) {
        columnsToRetype.push({ from: liveColumn, to: column });
      }
    }

    const declaredColumnNames = new Set(declaredTable.columns.map((c) => c.name));
    for (const liveColumn of liveTable.columns) {
      if (!declaredColumnNames.has(liveColumn.name)) {
        extraColumns.push({ table: declaredTable.name, column: liveColumn.name });
      }
    }

    const liveKeyNames = new Set(liveTable.keys.filter((k) => k.name).map((k) => k.name));
    const keysToAdd = declaredTable.keys.filter((k) => k.type !== 'PRIMARY' && k.name !== undefined && !liveKeyNames.has(k.name));

    const requiresRecreate = columnsToRetype.length > 0 || !samePrimaryKey(declaredTable, liveTable);

    if (columnsToAdd.length > 0 || keysToAdd.length > 0 || requiresRecreate) {
      tablesToAlter.push({ table: declaredTable.name, columnsToAdd, keysToAdd, columnsToRetype, requiresRecreate });
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
