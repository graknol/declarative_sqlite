import type { Database } from '../db/database';
import type { ServerWriter } from '../db/server-truth';
import { quoteIdentifier } from '../db/sql';
import { OUTBOX_TABLE } from '../schema/library-tables';
import type { Row } from '../types';
import { assertScalarFits, encodeScalar, MAX_BATCH_CHANGES } from './wire';

/** Where a recorded change stands. `applied`, `noop` and `rejected` are terminal; `rejected` stays visible until the user retries or discards it. */
export type OutboxStatus = 'pending' | 'sending' | 'applied' | 'noop' | 'rejected';

/** One recorded column change. `oldValue` is what the device saw and is informational; the server logs it and decides by arrival order. */
export interface OutboxEntry {
  id: string;
  tableName: string;
  systemId: string;
  columnName: string;
  oldValue: unknown;
  newValue: unknown;
  changedAt: string;
  status: OutboxStatus;
  groupId: string;
  batchId?: string;
  errorText?: string;
  appliedAt?: string;
}

/** One change group: every column of one row that must reach the server in the same batch. */
export interface RecordRequest {
  table: string;
  systemId: string;
  changes: Record<string, unknown>;
}

/** Thrown for a change the library refuses to record: a non-synced table, a missing row, an unknown column, an empty or oversized group. */
export class OutboxError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OutboxError';
  }
}

/**
 * The queue of recorded, unconfirmed changes — the second of the three owners of
 * state, between server truth in the tables and the draft being typed. Recording
 * writes the local row and the queue rows in one transaction, so what the user
 * sees and what will be sent can never disagree. Reads of a synced table are
 * overlaid with the pending values (see `Overlay`), so a column stays at the
 * user's value until the server answers.
 */
export class Outbox {
  private readonly listeners = new Set<() => void>();
  /** Bumped on every write so the overlay knows its cache is stale. */
  version = 0;

  constructor(
    private readonly db: Database,
    private readonly writer: ServerWriter,
    private readonly options: { clock?: () => Date } = {},
  ) {}

  /**
   * Registers a listener called after every recorded change (and, once Task 19
   * lands, every status update). Returns an unsubscribe function. Used by the
   * overlay to invalidate its cache and by UI badges to re-render the pending
   * count without polling.
   */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /**
   * Records one change group: writes the new values into the local row and
   * appends one outbox entry per changed column, all in a single transaction,
   * then returns the group's id. Refuses a non-synced table, a row that does
   * not exist locally, a column the schema does not declare, an empty change
   * set, a value wider than the server accepts, or a group bigger than one
   * push batch can carry — none of these leave anything behind.
   */
  async record(request: RecordRequest): Promise<string> {
    const table = this.db.tableDef(request.table);
    if (!table.synced) throw new OutboxError(`Table ${request.table} is not synced; write it through db.tables instead`);

    const columns = Object.keys(request.changes);
    if (columns.length === 0) throw new OutboxError(`${request.table}/${request.systemId}: no changes to record`);
    if (columns.length > MAX_BATCH_CHANGES) {
      throw new OutboxError(
        `${request.table}/${request.systemId}: a change group of ${columns.length} columns cannot be pushed atomically (the cap is ${MAX_BATCH_CHANGES})`,
      );
    }
    for (const column of columns) {
      if (!table.columns.some((c) => c.name === column)) {
        throw new OutboxError(`${request.table}: column "${column}" is not in the schema`);
      }
    }

    const keyColumn = table.synced.key;
    const current = await this.db.queryOne<Row>(
      `SELECT * FROM ${quoteIdentifier(table.name)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
      [request.systemId],
    );
    if (!current) throw new OutboxError(`${request.table}/${request.systemId}: row does not exist locally`);

    const changedAt = (this.options.clock?.() ?? new Date()).toISOString();
    const groupId = crypto.randomUUID();

    const entries = columns.map((column) => {
      const newValue = encodeScalar(request.changes[column]);
      assertScalarFits(table.name, column, newValue);
      return {
        id: crypto.randomUUID(),
        column,
        oldValue: encodeScalar(current[column] ?? null),
        newValue,
      };
    });

    await this.db.transaction(async (tx) => {
      const values: Row = {};
      for (const column of columns) {
        values[column] = request.changes[column] as Row[string];
      }
      await this.writer.setColumns(tx, table.name, request.systemId, values);

      for (const entry of entries) {
        await tx.execute(
          `INSERT INTO ${quoteIdentifier(OUTBOX_TABLE)} (id, table_name, system_id, column_name, old_value, new_value, changed_at, status, group_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)`,
          [entry.id, table.name, request.systemId, entry.column, entry.oldValue, entry.newValue, changedAt, groupId],
        );
      }
      tx.markTableWritten(OUTBOX_TABLE);
    });

    this.notify();
    return groupId;
  }

  /** Bumps the version and tells subscribers (the overlay, the badge) that the queue changed. */
  protected notify(): void {
    this.version++;
    for (const listener of [...this.listeners]) {
      try {
        listener();
      } catch (error) {
        console.error('[declarative-sqlite] outbox listener failed', error);
      }
    }
  }
}
