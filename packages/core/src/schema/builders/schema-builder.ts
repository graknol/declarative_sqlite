import type { Schema, DbTable } from '../types';
import { TableBuilder } from './table-builder';

/**
 * Builder for database schemas
 */
export class SchemaBuilder {
  private tableBuilders: TableBuilder[] = [];
  
  /**
   * Define a table in the schema
   */
  table(name: string, build: (table: TableBuilder) => void): this {
    const builder = new TableBuilder(name);
    build(builder);
    this.tableBuilders.push(builder);
    return this;
  }
  
  /**
   * Build the final schema
   */
  build(): Schema {
    // Build user tables
    const userTables = this.tableBuilders
      .filter(t => !t.name.startsWith('__'))
      .map(t => t.build());
    
    // Add system tables
    const systemTables = this.buildSystemTables();
    
    // Compute schema version (hash of schema structure)
    const version = this.computeSchemaVersion([...userTables, ...systemTables]);
    
    return {
      tables: [...userTables, ...systemTables],
      views: [], // Views will be added in a future phase
      version,
    };
  }
  
  /**
   * Build system tables
   */
  private buildSystemTables(): DbTable[] {
    const tables: DbTable[] = [];
    
    // __settings table
    const settingsBuilder = new TableBuilder('__settings');
    settingsBuilder.text('key').notNull('_');
    settingsBuilder.text('value');
    settingsBuilder.key('key').primary();
    tables.push(settingsBuilder.build());
    
    // __files table
    const filesBuilder = new TableBuilder('__files');
    filesBuilder.text('id').notNull('');
    filesBuilder.text('fileset').notNull('');
    filesBuilder.text('filename').notNull('default');
    filesBuilder.text('mime_type').notNull('application/octet-stream');
    filesBuilder.integer('size').notNull(0);
    filesBuilder.text('created_at').notNull('');
    filesBuilder.text('modified_at').notNull('');
    filesBuilder.integer('version').notNull(1);
    filesBuilder.text('storage_path').notNull('');
    filesBuilder.key('id').primary();
    filesBuilder.key('fileset', 'filename').index();
    tables.push(filesBuilder.build());
    
    // __dirty_rows table
    const dirtyRowsBuilder = new TableBuilder('__dirty_rows');
    dirtyRowsBuilder.text('table_name').notNull('');
    dirtyRowsBuilder.guid('row_id').notNull('00000000-0000-0000-0000-000000000000');
    dirtyRowsBuilder.text('hlc').notNull('');
    dirtyRowsBuilder.integer('is_full_row').notNull(1);
    dirtyRowsBuilder.key('table_name', 'row_id').primary();
    tables.push(dirtyRowsBuilder.build());
    
    return tables;
  }
  
  /**
   * Compute a version hash for the schema
   */
  private computeSchemaVersion(tables: DbTable[]): string {
    // Simple hash based on schema structure
    const schemaString = JSON.stringify({
      tables: tables.map(t => ({
        name: t.name,
        columns: t.columns.map(c => ({ name: c.name, type: c.type })),
        keys: t.keys,
      })),
    });
    
    // Simple hash function
    let hash = 0;
    for (let i = 0; i < schemaString.length; i++) {
      hash = ((hash << 5) - hash) + schemaString.charCodeAt(i);
      hash = hash & hash; // Convert to 32-bit integer
    }
    
    return Math.abs(hash).toString(36);
  }
}
