import type { SQLiteAdapter } from '../adapters/adapter';
import type { Schema } from '../schema/types';
import { diffSchema, type MigrationDiff } from './diff';
import { generateMigration, type MigrationOperation } from './generate';
import { introspect } from './introspect';

/** `auto` migrates, `plan` computes the operations and executes nothing, `off` skips the whole step. */
export type MigrationMode = 'auto' | 'plan' | 'off';

/** What a migration decided: the diff behind it, the statements it produced, and whether they were executed. */
export interface MigrationPlan {
  diff: MigrationDiff;
  operations: MigrationOperation[];
  hasOperations: boolean;
  applied: boolean;
}

/**
 * Computes what would happen without touching the database. Useful in a startup
 * log, in tests, and as the `plan` mode of `Database.open`.
 */
export async function planMigration(
  adapter: SQLiteAdapter,
  declared: Schema,
  options: { allowRecreate?: boolean } = {},
): Promise<MigrationPlan> {
  const live = await introspect(adapter);
  const diff = diffSchema(declared, live);
  const operations = generateMigration(diff, declared, { allowRecreate: options.allowRecreate ?? false });
  return { diff, operations, hasOperations: operations.length > 0, applied: false };
}

/**
 * Brings the database up to the declared schema. Every statement runs inside one
 * transaction, so a migration either lands whole or not at all — a half-migrated
 * database is the one failure mode an offline app cannot recover from on its
 * own. `onPlan` is called with the plan before anything executes, which is how
 * an app logs what its users' databases are doing.
 */
export async function runMigration(
  adapter: SQLiteAdapter,
  declared: Schema,
  options: { mode: MigrationMode; allowRecreate?: boolean; onPlan?: (plan: MigrationPlan) => void },
): Promise<MigrationPlan> {
  if (options.mode === 'off') {
    const live = await introspect(adapter);
    return { diff: diffSchema(declared, live), operations: [], hasOperations: false, applied: false };
  }

  const plan = await planMigration(adapter, declared, { allowRecreate: options.allowRecreate ?? false });
  options.onPlan?.(plan);

  if (options.mode === 'plan' || !plan.hasOperations) return plan;

  await adapter.exec('BEGIN IMMEDIATE');
  try {
    for (const operation of plan.operations) {
      for (const sql of operation.sql) await adapter.exec(sql);
    }
    await adapter.exec('COMMIT');
  } catch (error) {
    await adapter.exec('ROLLBACK');
    throw error;
  }

  return { ...plan, applied: true };
}
