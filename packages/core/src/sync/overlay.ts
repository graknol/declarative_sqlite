import type { Database } from '../db/database';
import { toSqlValue } from '../db/tables';
import type { Row } from '../types';
import type { Outbox } from './outbox';

/**
 * Makes reads of a synced table show what the user did, not what the server last
 * said: every column with a `pending` or `sending` outbox entry is replaced by
 * the recorded value. Applied inside the live layer before emission, so no
 * consumer can observe raw server truth for a column the outbox owns. A column
 * whose change was answered — applied, noop or rejected — is no longer pending,
 * so server truth shows through again and a rejection becomes visible.
 */
export class Overlay {
  constructor(
    private readonly db: Database,
    private readonly outbox: Outbox,
  ) {}

  /**
   * Overlays unconfirmed outbox values onto `rows` read from `table`. Rows of a
   * table with no `.synced()` declaration, and rows with nothing pending, are
   * returned untouched (same array, same row identity) so callers that rely on
   * reference equality to skip re-rendering are not defeated by a no-op pass.
   */
  apply(table: string, rows: Row[]): Row[] {
    const def = this.db.schema.tables.find((t) => t.name === table);
    if (!def?.synced) return rows;
    const keyColumn = def.synced.key;

    let changed = false;
    const result = rows.map((row) => {
      const systemId = String(row[keyColumn] ?? '');
      if (!systemId) return row;
      const columns = this.outbox.pendingColumns(table, systemId);
      if (columns.size === 0) return row;
      const overlaid: Row = { ...row };
      let rowChanged = false;
      for (const column of columns) {
        if (!(column in row)) continue;
        const pending = this.outbox.pendingValue(table, systemId, column);
        if (!pending) continue;
        overlaid[column] = toSqlValue(pending.value);
        rowChanged = true;
      }
      if (!rowChanged) return row;
      changed = true;
      return overlaid;
    });

    return changed ? result : rows;
  }
}
