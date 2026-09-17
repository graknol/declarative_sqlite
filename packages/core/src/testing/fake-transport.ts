import type { SyncTransport } from '../sync/transport';
import { DEFAULT_PAGE_LIMIT, type PullRequest, type PushBatch, type PushChangeResult, type PushResult, type RowDoc, type RowsPage } from '../sync/wire';

interface ServerRow {
  id: string;
  seq: number;
  removed: boolean;
  data: Record<string, unknown>;
}

/**
 * A scripted server for tests. It behaves the way `wire-format.md` says the real
 * one does: rows carry a monotonic `seq`, a push applies its changes in order
 * with last arrival winning per column, the answer rows are the state as that
 * batch left them, and a replayed `batchId` returns the stored answer without
 * applying anything. `serverEdit` and `tombstone` simulate the other device.
 */
export class FakeTransport implements SyncTransport {
  private readonly tables = new Map<string, Map<string, ServerRow>>();
  private readonly answers = new Map<string, PushResult>();
  private readonly rejections = new Map<string, string>();
  private seq = 0;
  private failPush: Error | undefined;

  /** Every batch ever passed to `push`, in call order, for assertions in tests. */
  readonly pushes: PushBatch[] = [];
  /** Every request ever passed to `pullRows`, in call order, for assertions in tests. */
  readonly pulls: PullRequest[] = [];

  constructor(private readonly options: { pageSize?: number } = {}) {}

  /** Seeds a table with rows as if they already existed on the server, each getting the next sequence number. */
  seed(table: string, rows: Array<{ id: string; data: Record<string, unknown>; removed?: boolean }>): void {
    for (const row of rows) {
      this.rowsOf(table).set(row.id, { id: row.id, seq: ++this.seq, removed: row.removed ?? false, data: { ...row.data } });
    }
  }

  /** Another device changed the row on the server: bumps its seq the way a real `Update___` would. */
  serverEdit(table: string, id: string, data: Record<string, unknown>): void {
    const row = this.rowsOf(table).get(id);
    if (!row) throw new Error(`FakeTransport: no row ${table}/${id}`);
    row.data = { ...row.data, ...data };
    row.seq = ++this.seq;
  }

  /** Marks a row removed on the server, the way a delete shows up on the next pull: `removed: true` with empty data. */
  tombstone(table: string, id: string): void {
    const row = this.rowsOf(table).get(id);
    if (!row) throw new Error(`FakeTransport: no row ${table}/${id}`);
    row.removed = true;
    row.seq = ++this.seq;
  }

  /** Makes every push of this column come back `rejected` with the given error, like an IFS validation failure. */
  reject(table: string, column: string, error: string): void {
    this.rejections.set(`${table}.${column}`, error);
  }

  /** Makes the next call to `push` reject with `error` instead of touching any row, then behaves normally again. */
  failNextPush(error: Error = new Error('network')): void {
    this.failPush = error;
  }

  /** Returns rows for `req.table` with `seq > req.after`, restricted to `req.scope` when given, paged by `pageSize`. */
  async pullRows(req: PullRequest): Promise<RowsPage> {
    this.pulls.push(req);
    const limit = req.limit ?? this.options.pageSize ?? DEFAULT_PAGE_LIMIT;
    const scope = req.scope ? parseWireScope(req.scope) : undefined;

    const all = [...this.rowsOf(req.table).values()]
      .filter((row) => row.seq > req.after)
      .filter((row) => matchesScope(row, scope))
      .sort((a, b) => a.seq - b.seq);

    const page = all.slice(0, limit);
    const last = page[page.length - 1];
    return {
      table: req.table,
      rows: page.map(toRowDoc),
      next: last ? last.seq : req.after,
      hasMore: all.length > page.length,
    };
  }

  /**
   * Applies a batch's changes in order, last write per column winning, and answers with the
   * per-change verdicts plus the current state of every row the batch touched. Replaying a
   * `batchId` that was already stored returns that same stored answer and touches nothing.
   */
  async push(batch: PushBatch): Promise<PushResult> {
    this.pushes.push(batch);
    if (this.failPush) {
      const error = this.failPush;
      this.failPush = undefined;
      throw error;
    }
    const stored = this.answers.get(batch.batchId);
    if (stored) return stored;

    const results: PushChangeResult[] = [];
    const touched = new Map<string, ServerRow>();

    for (const [index, change] of batch.changes.entries()) {
      const row = this.rowsOf(change.table).get(change.id);
      if (!row || row.removed) {
        results.push({ index, result: 'rejected', error: `CNOROW: row ${change.id} does not exist on the server` });
        continue;
      }
      const rejection = this.rejections.get(`${change.table}.${change.column}`);
      if (rejection) {
        results.push({ index, result: 'rejected', error: rejection });
        continue;
      }
      touched.set(`${change.table}|${change.id}`, row);
      if (Object.is(row.data[change.column] ?? null, change.new ?? null)) {
        results.push({ index, result: 'noop', error: null });
        continue;
      }
      row.data[change.column] = change.new;
      row.seq = ++this.seq;
      results.push({ index, result: 'applied', error: null });
    }

    const rows = [...touched.values()].map(toRowDoc);

    const answer: PushResult = { batchId: batch.batchId, results, rows };
    this.answers.set(batch.batchId, answer);
    return answer;
  }

  private rowsOf(table: string): Map<string, ServerRow> {
    let rows = this.tables.get(table);
    if (!rows) {
      rows = new Map();
      this.tables.set(table, rows);
    }
    return rows;
  }
}

function toRowDoc(row: ServerRow): RowDoc {
  return { id: row.id, seq: row.seq, removed: row.removed, data: row.removed ? {} : { ...row.data } };
}

function parseWireScope(scope: string): Record<string, string> {
  const parsed: Record<string, string> = {};
  for (const pair of scope.split(',')) {
    const at = pair.indexOf(':');
    parsed[pair.slice(0, at)] = pair.slice(at + 1);
  }
  return parsed;
}

function matchesScope(row: ServerRow, scope?: Record<string, string>): boolean {
  if (!scope) return true;
  return Object.entries(scope).every(([column, value]) => String(row.data[column] ?? '') === value);
}
