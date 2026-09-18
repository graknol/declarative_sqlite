import type { Database } from '../db/database';
import type { ServerWriter } from '../db/server-truth';
import { quoteIdentifier } from '../db/sql';
import { OUTBOX_TABLE } from '../schema/library-tables';
import type { Row } from '../types';
import { assertScalarFits, decodeScalar, encodeScalar, MAX_BATCH_CHANGES, newBatchId, type PushChangeResult } from './wire';

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
    // newBatchId() (not crypto.randomUUID() directly) because randomUUID is
    // absent in older Node, in a web view served over plain HTTP, and in some
    // React Native engines; it falls back through getRandomValues and
    // Math.random() to the same canonical 36-character form.
    const groupId = newBatchId();

    const entries = columns.map((column) => {
      const newValue = encodeScalar(request.changes[column]);
      assertScalarFits(table.name, column, newValue);
      return {
        id: newBatchId(),
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
      // Through onCommit, not after the await: `record` is called from inside
      // Drafts.endRow's transaction, and a nested db.transaction() resolves
      // when its own body ends, not when the outer COMMIT is decided. Mutating
      // the index there would leave a column reading as pending after a later
      // step of that outer transaction rolled the insert away.
      tx.onCommit(() => {
        for (const entry of entries) {
          this.indexPut(table.name, request.systemId, entry.column, entry.id, request.changes[entry.column]);
        }
        this.notify();
      });
    });

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

  /** table|systemId -> column -> the outbox entry currently holding that column's pending value. The table is durable truth; this is only a fast read of it. */
  private readonly index = new Map<string, Map<string, { entryId: string; value: unknown }>>();

  private static indexKey(table: string, systemId: string): string {
    return `${table}|${systemId}`;
  }

  /**
   * Reads every `pending`/`sending` row into the in-memory index. Call once
   * after opening the database, before the first read of `pendingColumns` or
   * `pendingValue` — those two are synchronous because the overlay calls them
   * for every row of every emission, and a database round trip there would
   * not scale.
   */
  async load(): Promise<void> {
    this.index.clear();
    const rows = await this.db.query<{ id: string; table_name: string; system_id: string; column_name: string; new_value: string | null }>(
      `SELECT id, table_name, system_id, column_name, new_value FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE status IN ('pending','sending') ORDER BY changed_at`,
    );
    for (const row of rows) this.indexPut(row.table_name, row.system_id, row.column_name, row.id, decodeScalar(row.new_value));
    this.notify();
  }

  private indexPut(table: string, systemId: string, column: string, entryId: string, value: unknown): void {
    const key = Outbox.indexKey(table, systemId);
    let columns = this.index.get(key);
    if (!columns) {
      columns = new Map();
      this.index.set(key, columns);
    }
    columns.set(column, { entryId, value });
  }

  private indexRemove(table: string, systemId: string, column: string, entryId: string): void {
    const key = Outbox.indexKey(table, systemId);
    const columns = this.index.get(key);
    const current = columns?.get(column);
    if (!columns || !current || current.entryId !== entryId) return;
    columns.delete(column);
    if (columns.size === 0) this.index.delete(key);
  }

  /** The columns of this row that are recorded but unconfirmed. Synchronous: the overlay calls it for every row of every emission. */
  pendingColumns(table: string, systemId: string): ReadonlySet<string> {
    return new Set(this.index.get(Outbox.indexKey(table, systemId))?.keys() ?? []);
  }

  /** The value the outbox holds for one column, or `undefined` when nothing is pending for it. Synchronous, from the index. */
  pendingValue(table: string, systemId: string, column: string): { value: unknown } | undefined {
    const entry = this.index.get(Outbox.indexKey(table, systemId))?.get(column);
    return entry ? { value: entry.value } : undefined;
  }

  /** Whether any column of this row is unconfirmed. Synchronous, from the index. */
  hasPending(table: string, systemId: string): boolean {
    return this.index.has(Outbox.indexKey(table, systemId));
  }

  /** All entries currently `pending`, oldest first. */
  async pending(): Promise<OutboxEntry[]> {
    return this.entries({ status: 'pending' });
  }

  /** Reads outbox rows from the table, oldest first, optionally filtered by status. This is the durable truth; `pendingColumns`/`pendingValue` are the fast in-memory read of it. */
  async entries(filter: { status?: OutboxStatus } = {}): Promise<OutboxEntry[]> {
    const where = filter.status ? ' WHERE status = ?' : '';
    const params = filter.status ? [filter.status] : [];
    const rows = await this.db.query<Record<string, string | null>>(
      // rowid, not id, breaks ties: two columns of the same record() call share
      // one changed_at, and id is a random UUID with no relation to insertion
      // order, so id would make "oldest first" nondeterministic between runs.
      `SELECT * FROM ${quoteIdentifier(OUTBOX_TABLE)}${where} ORDER BY changed_at, rowid`,
      params,
    );
    return rows.map(toEntry);
  }

  /**
   * Moves a set of `pending` entries to `sending` under one batch id, marking
   * them as in flight to the server. The index is untouched: a sending entry
   * is still unconfirmed, so its column still reads as pending.
   */
  async markSending(ids: string[], batchId: string): Promise<void> {
    if (ids.length === 0) return;
    await this.db.transaction(async (tx) => {
      for (const id of ids) {
        await tx.execute(
          `UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = 'sending', batch_id = ? WHERE id = ? AND status = 'pending'`,
          [batchId, id],
        );
      }
      tx.markTableWritten(OUTBOX_TABLE);
    });
    this.notify();
  }

  /**
   * Writes the server's verdict on one batch. `order` is the entry ids in the
   * order the batch listed them, so `results[i].index` names an entry. An entry
   * the answer says nothing about goes back to `pending` and is sent again —
   * the server answers every change it received, so a gap means it never got it.
   * Every update is scoped to `WHERE ... AND batch_id = ?` so a stale or
   * duplicate answer for a batch id that has already been superseded (the
   * entry was retried, reset, or answered again under a new batch) touches
   * nothing.
   */
  async applyResults(batchId: string, results: PushChangeResult[], order: string[]): Promise<void> {
    const appliedAt = (this.options.clock?.() ?? new Date()).toISOString();
    const answered = new Set<string>();

    await this.db.transaction(async (tx) => {
      for (const result of results) {
        const id = order[result.index];
        if (!id) continue;
        answered.add(id);
        const status: OutboxStatus = result.result === 'rejected' ? 'rejected' : result.result;
        await tx.execute(
          `UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = ?, error_text = ?, applied_at = ? WHERE id = ? AND batch_id = ?`,
          [status, result.error ?? null, appliedAt, id, batchId],
        );
      }
      for (const id of order) {
        if (answered.has(id)) continue;
        await tx.execute(
          `UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = 'pending', batch_id = NULL WHERE id = ? AND batch_id = ?`,
          [id, batchId],
        );
      }
      tx.markTableWritten(OUTBOX_TABLE);

      // The re-query runs inside the transaction (it sees the updates above) so
      // that the whole index mutation can be deferred to onCommit: read the
      // still-matching rows now, remove them from the index only once the
      // outermost transaction has really committed.
      const settled: Array<{ id: string; table_name: string; system_id: string; column_name: string }> = [];
      for (const id of answered) {
        const row = await tx.queryOne<{ table_name: string; system_id: string; column_name: string }>(
          `SELECT table_name, system_id, column_name FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE id = ? AND batch_id = ?`,
          [id, batchId],
        );
        if (row) settled.push({ id, ...row });
      }
      tx.onCommit(() => {
        for (const row of settled) this.indexRemove(row.table_name, row.system_id, row.column_name, row.id);
        this.notify();
      });
    });
  }

  /** A network error: the batch never reached a verdict, so its entries queue again. The push service re-sends them under the same batch id. */
  async resetSending(batchId: string): Promise<void> {
    await this.db.transaction(async (tx) => {
      await tx.execute(`UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = 'pending' WHERE batch_id = ? AND status = 'sending'`, [batchId]);
      tx.markTableWritten(OUTBOX_TABLE);
    });
    this.notify();
  }

  /** The user drops a rejected change. The local column keeps the user's value until the next pull overwrites it with server truth. */
  async discard(id: string): Promise<void> {
    const row = await this.db.queryOne<{ table_name: string; system_id: string; column_name: string }>(
      `SELECT table_name, system_id, column_name FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE id = ?`,
      [id],
    );
    await this.db.transaction(async (tx) => {
      await tx.execute(`DELETE FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE id = ?`, [id]);
      tx.markTableWritten(OUTBOX_TABLE);
      tx.onCommit(() => {
        if (row) this.indexRemove(row.table_name, row.system_id, row.column_name, id);
        this.notify();
      });
    });
  }

  /** The user retries a rejected change: back to `pending`, error cleared, index restored. */
  async retry(id: string): Promise<void> {
    const row = await this.db.queryOne<{ table_name: string; system_id: string; column_name: string; new_value: string | null }>(
      `SELECT table_name, system_id, column_name, new_value FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE id = ?`,
      [id],
    );
    if (!row) return;
    await this.db.transaction(async (tx) => {
      await tx.execute(
        `UPDATE ${quoteIdentifier(OUTBOX_TABLE)} SET status = 'pending', error_text = NULL, batch_id = NULL, applied_at = NULL WHERE id = ?`,
        [id],
      );
      tx.markTableWritten(OUTBOX_TABLE);
      tx.onCommit(() => {
        this.indexPut(row.table_name, row.system_id, row.column_name, id, decodeScalar(row.new_value));
        this.notify();
      });
    });
  }

  /** Counts of entries by status, for the sync badge. */
  async counts(): Promise<{ pending: number; sending: number; rejected: number }> {
    const rows = await this.db.query<{ status: OutboxStatus; n: number }>(
      `SELECT status, COUNT(*) AS n FROM ${quoteIdentifier(OUTBOX_TABLE)} GROUP BY status`,
    );
    const counts = { pending: 0, sending: 0, rejected: 0 };
    for (const row of rows) {
      if (row.status === 'pending') counts.pending = row.n;
      else if (row.status === 'sending') counts.sending = row.n;
      else if (row.status === 'rejected') counts.rejected = row.n;
    }
    return counts;
  }

  /** Deletes settled history (`applied`/`noop`) older than `days`. Rejected entries are never purged: they are waiting for the user. */
  async purgeOlderThan(days: number, now: Date = this.options.clock?.() ?? new Date()): Promise<number> {
    const cutoff = new Date(now.getTime() - days * 24 * 60 * 60 * 1000).toISOString();
    const result = await this.db.execute(
      `DELETE FROM ${quoteIdentifier(OUTBOX_TABLE)} WHERE status IN ('applied','noop') AND changed_at < ?`,
      [cutoff],
      { invalidates: [OUTBOX_TABLE] },
    );
    this.notify();
    return result.changes;
  }
}

/** Maps one raw outbox row to an `OutboxEntry`, dropping optional fields the row does not have rather than setting them to `null`. */
function toEntry(row: Record<string, string | null>): OutboxEntry {
  return {
    id: row['id'] ?? '',
    tableName: row['table_name'] ?? '',
    systemId: row['system_id'] ?? '',
    columnName: row['column_name'] ?? '',
    oldValue: decodeScalar(row['old_value'] ?? null),
    newValue: decodeScalar(row['new_value'] ?? null),
    changedAt: row['changed_at'] ?? '',
    status: (row['status'] ?? 'pending') as OutboxStatus,
    groupId: row['group_id'] ?? '',
    ...(row['batch_id'] ? { batchId: row['batch_id'] } : {}),
    ...(row['error_text'] ? { errorText: row['error_text'] } : {}),
    ...(row['applied_at'] ? { appliedAt: row['applied_at'] } : {}),
  };
}
