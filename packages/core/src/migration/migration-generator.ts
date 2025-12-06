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
   */
  generateMigration(diff: SchemaDiff): MigrationOperation[] {
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
        operations.push(...this.generateTableRecreation(alterations));
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
   */
  private generateCreateTable(table: DbTable): MigrationOperation {
    const sql: string[] = [];
    
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
    sql.push(`CREATE TABLE "${table.name}" (\n  ${allDefs.join(',\n  ')}\n)`);

    // Create indices
    for (const key of table.keys) {
      if (key.type === 'INDEX') {
        const indexName = key.name || `idx_${table.name}_${key.columns.join('_')}`;
        const columns = key.columns.map(c => `"${c}"`).join(', ');
        sql.push(`CREATE INDEX "${indexName}" ON "${table.name}" (${columns})`);
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
   * 2. Copy data from old table
   * 3. Drop old table
   * 4. Rename new table
   */
  private generateTableRecreation(alterations: TableAlterations): MigrationOperation[] {
    const operations: MigrationOperation[] = [];
    const tempTableName = `${alterations.tableName}_new`;

    // Note: We'll need the full new table definition
    // For now, generate placeholder operations
    operations.push({
      description: `Recreate table: ${alterations.tableName} (complex alterations)`,
      sql: [
        `-- Table ${alterations.tableName} requires recreation`,
        `-- This would:`,
        `-- 1. Create ${tempTableName} with new structure`,
        `-- 2. Copy data from ${alterations.tableName}`,
        `-- 3. Drop ${alterations.tableName}`,
        `-- 4. Rename ${tempTableName} to ${alterations.tableName}`,
      ],
    });

    return operations;
  }
}
