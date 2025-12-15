import type { SchemaDiff, TableAlterations } from './schema-differ';
import type { DbTable, DbColumn } from '../schema/types';

/**
 * Represents a migration operation
 */
export interface MigrationOperation {
  description: string;
  sql: string[];
}

/**
 * Generates SQL migration scripts from schema differences
 */
export class MigrationGenerator {
  /**
   * Generate migration operations from schema diff
   * @param diff - The schema differences
   * @param declarativeSchema - The full declarative schema (needed for table recreation)
   */
  generateMigration(diff: SchemaDiff, declarativeSchema?: { tables: DbTable[] }): MigrationOperation[] {
    const operations: MigrationOperation[] = [];

    // Drop tables first (to avoid FK conflicts)
    for (const tableName of diff.tablesToDrop) {
      operations.push({
        description: `Drop table: ${tableName}`,
        sql: [`DROP TABLE IF EXISTS "${tableName}"`],
      });
    }

    // Alter existing tables
    for (const alterations of diff.tablesToAlter) {
      if (alterations.requiresRecreate) {
        const fullTableDef = declarativeSchema?.tables.find(t => t.name === alterations.tableName);
        operations.push(...this.generateTableRecreation(alterations, fullTableDef));
      } else {
        operations.push(...this.generateTableAlterations(alterations));
      }
    }

    // Create new tables
    for (const table of diff.tablesToCreate) {
      operations.push(this.generateCreateTable(table));
    }

    return operations;
  }

  /**
   * Generate CREATE TABLE statement
   * @param table - The table definition
   * @param tempName - Optional temporary table name for recreation flow
   */
  private generateCreateTable(table: DbTable, tempName?: string): MigrationOperation {
    const sql: string[] = [];
    const tableName = tempName || table.name;
    
    // Build column definitions
    const columnDefs: string[] = [];
    for (const column of table.columns) {
      columnDefs.push(this.generateColumnDefinition(column));
    }

    // Build key definitions
    const keyDefs: string[] = [];
    for (const key of table.keys) {
      if (key.type === 'PRIMARY') {
        const columns = key.columns.map(c => `"${c}"`).join(', ');
        keyDefs.push(`PRIMARY KEY (${columns})`);
      } else if (key.type === 'UNIQUE') {
        const columns = key.columns.map(c => `"${c}"`).join(', ');
        keyDefs.push(`UNIQUE (${columns})`);
      }
    }

    // Combine all definitions
    const allDefs = [...columnDefs, ...keyDefs];
    sql.push(`CREATE TABLE "${tableName}" (\n  ${allDefs.join(',\n  ')}\n)`);

    // Create indices
    for (const key of table.keys) {
      if (key.type === 'INDEX') {
        const indexName = key.name || `idx_${table.name}_${key.columns.join('_')}`;
        const indexNameWithSuffix = tempName ? `${indexName}_temp` : indexName;
        const columns = key.columns.map(c => `"${c}"`).join(', ');
        sql.push(`CREATE INDEX "${indexNameWithSuffix}" ON "${tableName}" (${columns})`);
      }
    }

    return {
      description: `Create table: ${table.name}`,
      sql,
    };
  }

  /**
   * Generate column definition for CREATE TABLE
   */
  private generateColumnDefinition(column: DbColumn): string {
    let def = `"${column.name}" ${column.type}`;

    if (column.notNull) {
      def += ' NOT NULL';
      if (column.defaultValue !== undefined) {
        def += ` DEFAULT ${this.formatDefaultValue(column.defaultValue)}`;
      }
    }

    return def;
  }

  /**
   * Format default value for SQL
   */
  private formatDefaultValue(value: any): string {
    if (typeof value === 'string') {
      return `'${value.replace(/'/g, "''")}'`;
    }
    return String(value);
  }

  /**
   * Generate simple table alterations (ADD COLUMN, CREATE INDEX, DROP INDEX)
   */
  private generateTableAlterations(alterations: TableAlterations): MigrationOperation[] {
    const operations: MigrationOperation[] = [];

    // Add columns
    for (const column of alterations.columnsToAdd) {
      const columnDef = this.generateColumnDefinition(column);
      operations.push({
        description: `Add column: ${alterations.tableName}.${column.name}`,
        sql: [`ALTER TABLE "${alterations.tableName}" ADD COLUMN ${columnDef}`],
      });
    }

    // Drop indices
    for (const key of alterations.keysToDrop) {
      if (key.type === 'INDEX' && key.name) {
        operations.push({
          description: `Drop index: ${key.name}`,
          sql: [`DROP INDEX IF EXISTS "${key.name}"`],
        });
      }
    }

    // Create indices
    for (const key of alterations.keysToAdd) {
      if (key.type === 'INDEX') {
        const indexName = key.name || `idx_${alterations.tableName}_${key.columns.join('_')}`;
        const columns = key.columns.map(c => `"${c}"`).join(', ');
        operations.push({
          description: `Create index: ${indexName}`,
          sql: [`CREATE INDEX "${indexName}" ON "${alterations.tableName}" (${columns})`],
        });
      }
    }

    return operations;
  }

  /**
   * Generate table recreation (for complex alterations)
   * 
   * This uses the SQLite recommended approach:
   * 1. Create new table with desired structure
   * 2. Copy data from old table (for columns that exist in both)
   * 3. Drop old table
   * 4. Rename new table
   */
  private generateTableRecreation(alterations: TableAlterations, fullTableDef?: DbTable): MigrationOperation[] {
    const operations: MigrationOperation[] = [];
    
    // If we don't have the full table definition, fall back to simple column additions
    if (!fullTableDef) {
      console.warn(
        `Table ${alterations.tableName} requires recreation but full table definition not available. ` +
        `Falling back to simple column additions.`
      );
      
      if (alterations.columnsToModify.length > 0) {
        console.warn(
          `Skipping column modifications: ${alterations.columnsToModify.map(m => m.newColumn.name).join(', ')}`
        );
      }
      
      if (alterations.columnsToDrop.length > 0) {
        console.warn(
          `Skipping column drops: ${alterations.columnsToDrop.join(', ')}`
        );
      }
      
      operations.push(...this.generateTableAlterations(alterations));
      return operations;
    }
    
    const tableName = alterations.tableName;
    const tempTableName = `${tableName}_new`;
    const sql: string[] = [];
    
    // Step 1: Create new table with desired structure
    const createOp = this.generateCreateTable(fullTableDef, tempTableName);
    sql.push(...createOp.sql);
    
    // Step 2: Copy data from old table to new table
    // Only copy columns that exist in both old and new schemas
    const columnsToKeep: string[] = [];
    
    // Find columns that exist in both old and new (not dropped, not modified in incompatible ways)
    for (const col of fullTableDef.columns) {
      // Skip if this is a newly added column
      if (alterations.columnsToAdd.some(c => c.name === col.name)) {
        continue;
      }
      
      // Skip if this column is being dropped
      if (alterations.columnsToDrop.includes(col.name)) {
        continue;
      }
      
      // Include this column in the copy
      columnsToKeep.push(col.name);
    }
    
    if (columnsToKeep.length > 0) {
      const columnList = columnsToKeep.map(c => `"${c}"`).join(', ');
      sql.push(
        `INSERT INTO "${tempTableName}" (${columnList}) ` +
        `SELECT ${columnList} FROM "${tableName}"`
      );
    }
    
    // Step 3: Drop old table
    sql.push(`DROP TABLE "${tableName}"`);
    
    // Step 4: Rename new table to old table name
    sql.push(`ALTER TABLE "${tempTableName}" RENAME TO "${tableName}"`);
    
    // Step 5: Recreate indices with proper names
    for (const key of fullTableDef.keys) {
      if (key.type === 'INDEX') {
        const indexName = key.name || `idx_${tableName}_${key.columns.join('_')}`;
        const columns = key.columns.map(c => `"${c}"`).join(', ');
        sql.push(`DROP INDEX IF EXISTS "${indexName}_temp"`);
        sql.push(`CREATE INDEX "${indexName}" ON "${tableName}" (${columns})`);
      }
    }
    
    operations.push({
      description: `Recreate table: ${tableName} (${this.describeAlterations(alterations)})`,
      sql,
    });
    
    return operations;
  }
  
  /**
   * Generate a human-readable description of alterations
   */
  private describeAlterations(alterations: TableAlterations): string {
    const changes: string[] = [];
    
    if (alterations.columnsToAdd.length > 0) {
      changes.push(`${alterations.columnsToAdd.length} column(s) added`);
    }
    if (alterations.columnsToDrop.length > 0) {
      changes.push(`${alterations.columnsToDrop.length} column(s) dropped`);
    }
    if (alterations.columnsToModify.length > 0) {
      changes.push(`${alterations.columnsToModify.length} column(s) modified`);
    }
    if (alterations.keysToAdd.length > 0) {
      changes.push(`${alterations.keysToAdd.length} key(s) added`);
    }
    if (alterations.keysToDrop.length > 0) {
      changes.push(`${alterations.keysToDrop.length} key(s) dropped`);
    }
    
    return changes.join(', ');
  }
}
