import type { Database } from '../db/database';
import type { ServerWriter } from '../db/server-truth';
import { quoteIdentifier } from '../db/sql';
import type { Transaction } from '../db/transaction';
import { SYNC_SEQ_COLUMN, SYSTEM_REMOVED_COLUMN } from '../schema/table-builder';
import type { TableDef } from '../schema/types';
import type { Row, ScopeValues } from '../types';
import type { CursorStore } from './cursor-store';
import type { Drafts } from './drafts';
import type { Outbox } from './outbox';
import { fromWireData, type RowDoc, type RowsPage } from './wire';

/**
 * How a set of server rows should be applied. `scope` is passed through to the
 * cursor store so a scoped table's high-water mark is tracked per scope.
 * `advanceCursor` and `seqGuard` default differently for `applyPage` (a pull,
 * which is canonical and does not need the guard) and `applyRows` called
 * directly (a push answer, which is a receipt rather than a read and can lag
 * behind rows already pulled).
 */
export interface ApplyOptions {
  scope?: ScopeValues;
  /** Default true for `applyPage`, false for `applyRows`. */
  advanceCursor?: boolean;
  /** Skips a row whose `seq` is not above the local `sync_seq`. Default false for `applyPage`, true for `applyRows`. */
  seqGuard?: boolean;
}

/** What one apply did, for logs and tests. */
export interface ApplyReport {
  upserted: number;
  deleted: number;
  skippedBySeq: number;
  heldColumns: number;
  heldTombstones: number;
  keptPendingColumns: number;
}

function emptyReport(): ApplyReport {
  return { upserted: 0, deleted: 0, skippedBySeq: 0, heldColumns: 0, heldTombstones: 0, keptPendingColumns: 0 };
}

/**
 * The only path server truth takes into the local tables. One page is one
 * transaction and therefore one invalidation event, however many rows it
 * holds — every row of a page (or a push answer's receipt rows) is written
 * inside a single `db.transaction` body, so writes from `ServerWriter` join
 * that one transaction rather than each committing on their own. Two rules
 * protect what the user is doing, checked fresh for each row at the moment it
 * is about to be written rather than once for the whole page: a column with a
 * `pending` or `sending` outbox entry (`Outbox.pendingColumns`) keeps the
 * local value until the push answers, and a column being typed — or a
 * tombstone for a row being typed — is handed to `Drafts` to hold until the
 * draft ends.
 */
export class PullApplier {
  constructor(
    private readonly db: Database,
    private readonly writer: ServerWriter,
    private readonly outbox: Outbox,
    private readonly drafts: Drafts,
    private readonly cursors: CursorStore,
  ) {}

  /**
   * Applies one page from `GET /sync/rows` and advances the cursor to the
   * page's `next` unless told not to. The seq guard defaults off: a page is
   * the pull service's canonical answer, including any row it deliberately
   * re-sent under its rewind window, so it is always written rather than
   * compared against what is already local. The cursor update runs inside
   * the same transaction as the row writes (see `runInTransaction`), so a
   * page of any size is still exactly one commit and one invalidation.
   */
  async applyPage(table: string, page: RowsPage, options: ApplyOptions = {}): Promise<ApplyReport> {
    const { def, keyColumn } = this.syncedDef(table);
    const report = emptyReport();
    await this.runInTransaction(def, keyColumn, page.rows, options.seqGuard ?? false, report, async () => {
      if (options.advanceCursor !== false) await this.cursors.set(table, options.scope, page.next);
    });
    return report;
  }

  /**
   * Applies a set of `RowDoc`s in one transaction, honouring the outbox and
   * draft hand-over rules per row. Used directly (rather than through
   * `applyPage`) for a push answer's receipt rows, where the seq guard
   * defaults on and the cursor is not advanced unless asked to.
   */
  async applyRows(table: string, rows: RowDoc[], options: ApplyOptions = {}): Promise<ApplyReport> {
    const { def, keyColumn } = this.syncedDef(table);
    const report = emptyReport();
    await this.runInTransaction(def, keyColumn, rows, options.seqGuard ?? true, report, async () => {
      if (options.advanceCursor === true && rows.length > 0) {
        await this.cursors.set(table, options.scope, Math.max(...rows.map((r) => r.seq)));
      }
    });
    return report;
  }

  /** Looks up a table's definition and key column, throwing if the table is not `.synced()`. */
  private syncedDef(table: string): { def: TableDef; keyColumn: string } {
    const def = this.db.tableDef(table);
    if (!def.synced) throw new Error(`${table} is not a synced table`);
    return { def, keyColumn: def.synced.key };
  }

  /**
   * Writes every row in one transaction, then runs `afterRows` — the cursor
   * update — before that transaction commits. `CursorStore.set` opens its own
   * `db.transaction`, but a write from inside an open transaction joins it
   * rather than queuing, so calling it here rather than after this method
   * returns keeps the whole page, cursor included, as one commit and one
   * invalidation event.
   */
  private async runInTransaction(
    def: TableDef,
    keyColumn: string,
    rows: RowDoc[],
    seqGuard: boolean,
    report: ApplyReport,
    afterRows: () => Promise<void>,
  ): Promise<void> {
    await this.db.transaction(async (tx) => {
      for (const doc of rows) {
        await this.applyRow(tx, def, keyColumn, seqGuard, doc, report);
      }
      await afterRows();
    });
  }

  /** Applies one row: the seq guard, then a tombstone (deleted or held) or an upsert (column-guarded). */
  private async applyRow(
    tx: Transaction,
    def: TableDef,
    keyColumn: string,
    seqGuard: boolean,
    doc: RowDoc,
    report: ApplyReport,
  ): Promise<void> {
    const table = def.name;
    const existing = await tx.queryOne<Record<string, number>>(
      `SELECT ${quoteIdentifier(SYNC_SEQ_COLUMN)} FROM ${quoteIdentifier(table)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
      [doc.id],
    );
    if (seqGuard && existing && doc.seq <= Number(existing[SYNC_SEQ_COLUMN] ?? 0)) {
      report.skippedBySeq++;
      return;
    }

    if (doc.removed) {
      if (this.drafts.holdTombstone(table, doc.id)) {
        report.heldTombstones++;
        return;
      }
      report.deleted += await this.writer.delete(tx, table, doc.id);
      return;
    }

    await this.applyUpsert(tx, def, keyColumn, doc, report);
  }

  /**
   * Builds and writes the column set for one non-tombstoned row. A column
   * with a pending or sending outbox entry is dropped from the write; a
   * column being drafted is dropped too, but its server value is handed to
   * `Drafts.holdServerValue` first so it is not lost, only deferred. Both
   * checks are re-read from live state for this row right here rather than
   * hoisted before the loop, since either can change while an earlier row of
   * the same page is being written.
   */
  private async applyUpsert(tx: Transaction, def: TableDef, keyColumn: string, doc: RowDoc, report: ApplyReport): Promise<void> {
    const table = def.name;
    const values = fromWireData(def, doc.data);
    const pending = this.outbox.pendingColumns(table, doc.id);
    const drafted = this.drafts.activeColumns(table, doc.id);

    const write: Row = {};
    for (const [column, value] of Object.entries(values)) {
      if (pending.has(column)) {
        report.keptPendingColumns++;
        continue;
      }
      if (drafted.has(column)) {
        this.drafts.holdServerValue(table, doc.id, column, value);
        report.heldColumns++;
        continue;
      }
      write[column] = value;
    }

    write[keyColumn] = doc.id;
    write[SYNC_SEQ_COLUMN] = doc.seq;
    write[SYSTEM_REMOVED_COLUMN] = 0;
    await this.writer.upsert(tx, table, write);
    report.upserted++;
  }
}
