import type { Schema, DbTable, DbColumn, DbKey } from '../schema/types';

/**
 * Represents differences between declarative and live schemas
 */
export interface SchemaDiff {
  tablesToCreate: DbTable[];
  tablesToDrop: string[];
  tablesToAlter: TableAlterations[];
  hasChanges: boolean;
}

/**
 * Represents alterations needed for a specific table
 */
export interface TableAlterations {
  tableName: string;
  columnsToAdd: DbColumn[];
  columnsToDrop: string[];
  columnsToModify: ColumnModification[];
  keysToAdd: DbKey[];
  keysToDrop: DbKey[];
  requiresRecreate: boolean;
}

/**
 * Represents a modification to a column
 */
export interface ColumnModification {
  oldColumn: DbColumn;
  newColumn: DbColumn;
}

/**
 * Compares declarative schema with live schema to identify differences
 */
export class SchemaDiffer {
  /**
   * Compute the difference between declarative and live schemas
   */
  diff(declarativeSchema: Schema, liveSchema: Schema): SchemaDiff {
    const tablesToCreate: DbTable[] = [];
    const tablesToDrop: string[] = [];
    const tablesToAlter: TableAlterations[] = [];

    // Build maps for easier lookup
    const liveTableMap = new Map(liveSchema.tables.map(t => [t.name, t]));
    const declTableMap = new Map(declarativeSchema.tables.map(t => [t.name, t]));

    // Find tables to create (in declarative but not in live)
    for (const declTable of declarativeSchema.tables) {
      if (!liveTableMap.has(declTable.name)) {
        tablesToCreate.push(declTable);
      }
    }

    // Find tables to drop (in live but not in declarative)
    for (const liveTable of liveSchema.tables) {
      if (!declTableMap.has(liveTable.name)) {
        tablesToDrop.push(liveTable.name);
      }
    }

    // Find tables to alter (in both, but with differences)
    for (const declTable of declarativeSchema.tables) {
      const liveTable = liveTableMap.get(declTable.name);
      if (liveTable) {
        const alterations = this.diffTable(declTable, liveTable);
        if (this.hasAlterations(alterations)) {
          tablesToAlter.push(alterations);
        }
      }
    }

    return {
      tablesToCreate,
      tablesToDrop,
      tablesToAlter,
      hasChanges: tablesToCreate.length > 0 || tablesToDrop.length > 0 || tablesToAlter.length > 0,
    };
  }

  /**
   * Compare two tables to find differences
   */
  private diffTable(declTable: DbTable, liveTable: DbTable): TableAlterations {
    const columnsToAdd: DbColumn[] = [];
    const columnsToDrop: string[] = [];
    const columnsToModify: ColumnModification[] = [];
    const keysToAdd: DbKey[] = [];
    const keysToDrop: DbKey[] = [];

    // Build maps for columns
    const liveColumnMap = new Map(liveTable.columns.map(c => [c.name, c]));
    const declColumnMap = new Map(declTable.columns.map(c => [c.name, c]));

    // Find columns to add
    for (const declColumn of declTable.columns) {
      if (!liveColumnMap.has(declColumn.name)) {
        columnsToAdd.push(declColumn);
      }
    }

    // Find columns to drop
    for (const liveColumn of liveTable.columns) {
      if (!declColumnMap.has(liveColumn.name)) {
        columnsToDrop.push(liveColumn.name);
      }
    }

    // Find columns to modify
    for (const declColumn of declTable.columns) {
      const liveColumn = liveColumnMap.get(declColumn.name);
      if (liveColumn && !this.columnsEqual(declColumn, liveColumn)) {
        columnsToModify.push({
          oldColumn: liveColumn,
          newColumn: declColumn,
        });
      }
    }

    // Diff keys
    const { keysToAdd: addKeys, keysToDrop: dropKeys } = this.diffKeys(declTable.keys, liveTable.keys);
    keysToAdd.push(...addKeys);
    keysToDrop.push(...dropKeys);

    // Determine if table needs to be recreated
    const requiresRecreate = this.requiresTableRecreate({
      tableName: declTable.name,
      columnsToAdd,
      columnsToDrop,
      columnsToModify,
      keysToAdd,
      keysToDrop,
      requiresRecreate: false,
    });

    return {
      tableName: declTable.name,
      columnsToAdd,
      columnsToDrop,
      columnsToModify,
      keysToAdd,
      keysToDrop,
      requiresRecreate,
    };
  }

  /**
   * Check if two columns are equal
   * Only compares properties that affect the actual SQLite schema structure
   */
  private columnsEqual(col1: DbColumn, col2: DbColumn): boolean {
    return (
      col1.name === col2.name &&
      this.typesEqual(col1.type, col2.type) &&
      col1.notNull === col2.notNull &&
      this.defaultValuesEqual(col1.defaultValue, col2.defaultValue) &&
      this.lwwEqual(col1.lww, col2.lww)
    );
    // Note: We intentionally ignore maxLength, maxFileCount, maxFileSize
    // as these are application-level constraints, not SQLite schema
  }

  /**
   * Check if two column types are equal
   * SQLite has flexible typing, so we normalize type names
   */
  private typesEqual(type1: string, type2: string): boolean {
    const normalized1 = this.normalizeType(type1);
    const normalized2 = this.normalizeType(type2);
    return normalized1 === normalized2;
  }

  /**
   * Normalize SQLite type names
   * SQLite has type affinity rules, so TEXT/GUID/DATE all map to TEXT
   */
  private normalizeType(type: string): string {
    const upper = type.toUpperCase();
    // GUID and DATE are stored as TEXT in SQLite
    if (upper === 'GUID' || upper === 'DATE') return 'TEXT';
    return upper;
  }

  /**
   * Check if LWW status is equal
   * Treats undefined and false as equivalent
   */
  private lwwEqual(lww1: boolean | undefined, lww2: boolean | undefined): boolean {
    const val1 = lww1 ?? false;
    const val2 = lww2 ?? false;
    return val1 === val2;
  }

  /**
   * Check if two default values are equal
   * We're lenient here because:
   * 1. Schema introspection may not always return default values correctly
   * 2. Adding a default to an existing NOT NULL column is safe (only affects new rows)
   * 3. We want to avoid spurious table recreations
   */
  private defaultValuesEqual(val1: any, val2: any): boolean {
    if (val1 === val2) return true;
    if (val1 === undefined && val2 === undefined) return true;
    if (val1 === null && val2 === null) return true;
    
    // Treat undefined/null as equivalent when comparing defaults
    // This handles cases where introspection doesn't return a default
    if ((val1 === undefined || val1 === null) && (val2 === undefined || val2 === null)) {
      return true;
    }
    
    // Convert to strings for comparison
    return String(val1) === String(val2);
  }

  /**
   * Diff keys between two tables
   */
  private diffKeys(declKeys: DbKey[], liveKeys: DbKey[]): { keysToAdd: DbKey[]; keysToDrop: DbKey[] } {
    const keysToAdd: DbKey[] = [];
    const keysToDrop: DbKey[] = [];

    // Find keys to add
    for (const declKey of declKeys) {
      const matchingLiveKey = liveKeys.find(k => this.keysEqual(k, declKey));
      if (!matchingLiveKey) {
        keysToAdd.push(declKey);
      }
    }

    // Find keys to drop
    for (const liveKey of liveKeys) {
      const matchingDeclKey = declKeys.find(k => this.keysEqual(k, liveKey));
      if (!matchingDeclKey) {
        keysToDrop.push(liveKey);
      }
    }

    return { keysToAdd, keysToDrop };
  }

  /**
   * Check if two keys are equal
   */
  private keysEqual(key1: DbKey, key2: DbKey): boolean {
    return (
      key1.type === key2.type &&
      key1.columns.length === key2.columns.length &&
      key1.columns.every((col, idx) => col === key2.columns[idx])
    );
  }

  /**
   * Determine if table alterations require recreating the table
   * 
   * SQLite has limited ALTER TABLE support, so many changes require recreation:
   * - Dropping columns
   * - Modifying columns (type, constraints, etc.)
   * - Changing primary key
   */
  private requiresTableRecreate(alterations: TableAlterations): boolean {
    // Dropping columns requires recreation
    if (alterations.columnsToDrop.length > 0) {
      return true;
    }

    // Modifying columns requires recreation
    if (alterations.columnsToModify.length > 0) {
      return true;
    }

    // Changing primary key requires recreation
    const primaryKeyChanges = alterations.keysToAdd.some(k => k.type === 'PRIMARY') ||
                              alterations.keysToDrop.some(k => k.type === 'PRIMARY');
    if (primaryKeyChanges) {
      return true;
    }

    return false;
  }

  /**
   * Check if alterations object has any changes
   */
  private hasAlterations(alterations: TableAlterations): boolean {
    return (
      alterations.columnsToAdd.length > 0 ||
      alterations.columnsToDrop.length > 0 ||
      alterations.columnsToModify.length > 0 ||
      alterations.keysToAdd.length > 0 ||
      alterations.keysToDrop.length > 0
    );
  }
}
