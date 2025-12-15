import type { SQLiteAdapter } from '../adapters/adapter.interface';
import type { Schema } from '../schema/types';
import { SchemaIntrospector } from './schema-introspector';
import { SchemaDiffer } from './schema-differ';
import { MigrationGenerator, type MigrationOperation } from './migration-generator';
import type { SchemaDiff } from './schema-differ';

/**
 * Migration plan that can be previewed before execution
 */
export interface MigrationPlan {
  diff: SchemaDiff;
  operations: MigrationOperation[];
  hasOperations: boolean;
}

/**
 * Orchestrates schema migration
 */
export class SchemaMigrator {
  private introspector: SchemaIntrospector;
  private differ: SchemaDiffer;
  private generator: MigrationGenerator;

  constructor(private adapter: SQLiteAdapter) {
    this.introspector = new SchemaIntrospector(adapter);
    this.differ = new SchemaDiffer();
    this.generator = new MigrationGenerator();
  }

  /**
   * Plan migration without executing it
   * Useful for previewing changes before applying
   */
  async planMigration(declarativeSchema: Schema): Promise<MigrationPlan> {
    // Introspect live schema
    const liveTables = await this.introspector.getTables();
    const liveSchema: Schema = {
      tables: liveTables,
      views: [],
      version: '',
    };

    // Compute diff
    const diff = this.differ.diff(declarativeSchema, liveSchema);

    // Generate operations (pass declarative schema for table recreation)
    const operations = this.generator.generateMigration(diff, declarativeSchema);

    return {
      diff,
      operations,
      hasOperations: operations.length > 0,
    };
  }

  /**
   * Execute migration
   * Applies all changes within a single transaction for atomicity
   */
  async migrate(declarativeSchema: Schema): Promise<void> {
    const plan = await this.planMigration(declarativeSchema);

    if (!plan.hasOperations) {
      return; // No changes needed
    }

    // Execute all operations within a transaction
    await this.adapter.transaction(async () => {
      for (const operation of plan.operations) {
        for (const sql of operation.sql) {
          // Skip comment lines
          if (sql.trim().startsWith('--')) {
            continue;
          }
          
          await this.adapter.exec(sql);
        }
      }
    });
  }

  /**
   * Check if migration is needed
   */
  async isMigrationNeeded(declarativeSchema: Schema): Promise<boolean> {
    const plan = await this.planMigration(declarativeSchema);
    return plan.hasOperations;
  }
}
