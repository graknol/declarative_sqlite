import { TableBuilder } from './table-builder';
import type { TableDef } from './types';

/** The queue of recorded, unconfirmed changes. Owned by the library; the app never declares or writes it directly. */
export const OUTBOX_TABLE = 'outbox';
/** One row per `(table, scope)` the device has pulled, holding that scope's high-water `SYNC_SEQ`. */
export const SYNC_CURSOR_TABLE = 'sync_cursor';

/**
 * Builds the two tables this package owns. They are appended to every schema by
 * `SchemaBuilder.build()`, so automatic migration creates them on first open and
 * the application's `schema.ts` never mentions them.
 */
export function buildLibraryTables(): TableDef[] {
  const outbox = new TableBuilder(OUTBOX_TABLE);
  outbox.markLibrary();
  outbox.text('id').notNull('');
  outbox.text('table_name').notNull('');
  outbox.text('system_id').notNull('');
  outbox.text('column_name').notNull('');
  outbox.text('old_value');
  outbox.text('new_value');
  outbox.text('changed_at').notNull('');
  outbox.text('status').notNull('pending');
  outbox.text('group_id').notNull('');
  outbox.text('batch_id');
  outbox.text('error_text');
  outbox.text('applied_at');
  outbox.key('id').primary();
  outbox.key('status', 'changed_at').index();
  outbox.key('table_name', 'system_id', 'status').index();

  const cursor = new TableBuilder(SYNC_CURSOR_TABLE);
  cursor.markLibrary();
  cursor.text('scope_key').notNull('');
  cursor.text('table_name').notNull('');
  cursor.text('scope');
  cursor.integer('last_sync_seq').notNull(0);
  cursor.text('synced_at').notNull('');
  cursor.key('scope_key').primary();

  return [outbox.build(), cursor.build()];
}
