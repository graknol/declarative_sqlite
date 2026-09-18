import type { Database } from '../db/database';
import type { Outbox, OutboxEntry } from './outbox';
import type { PullApplier } from './pull-applier';
import type { SyncTransport } from './transport';
import { MAX_BATCH_CHANGES, newBatchId, toWireColumn, toWireTable, type PushBatch, type PushChange, type RowDoc } from './wire';

/** What the app shows in the header: are we online, is a push in flight, and when does the next retry happen. */
export interface SyncStatus {
  online: boolean;
  sending: boolean;
  attempt: number;
  nextRetryAt: number | null;
  lastError: string | null;
}

/** Totals from one `pushNow()` run, for logs and tests: how many changes were applied, no-opped or rejected, across how many batches. */
export interface PushOutcome {
  applied: number;
  noop: number;
  rejected: number;
  batches: number;
}

/** Tuning knobs for `PushService`. Only `deviceId` is required; the rest have production defaults. */
export interface PushServiceOptions {
  deviceId: string;
  /** Default 2000 ms. */
  debounceMs?: number;
  /** Default 500, the server's cap. */
  maxChangesPerBatch?: number;
  /** Default [5000, 30000, 120000]; the last value repeats until the app reports it is online again. */
  backoffMs?: number[];
  /** Decides whether a thrown transport error is terminal (a 4xx) rather than a network blip. Default: everything is retryable. */
  isTerminalError?: (error: unknown) => boolean;
}

interface PreparedBatch {
  batchId: string;
  entries: OutboxEntry[];
}

/**
 * Sends recorded changes and files the answers. It debounces (2 s by default),
 * builds batches that never split a change group, marks entries `sending` under
 * one batch id, and applies the answer through the pull applier with the
 * seq-monotonic guard — a push answer is a receipt of what that batch did, not a
 * read of the current row. A network error returns the entries to `pending` and
 * retries the SAME batch id, which the server answers idempotently, with backoff
 * 5 s / 30 s / 2 min until the app reports it is online again.
 */
export class PushService {
  private timer: ReturnType<typeof setTimeout> | undefined;
  private inFlight: Promise<PushOutcome> | undefined;
  private retryBatch: PreparedBatch | undefined;
  private state: SyncStatus = { online: true, sending: false, attempt: 0, nextRetryAt: null, lastError: null };
  private readonly statusListeners = new Set<(status: SyncStatus) => void>();
  private readonly rejectedListeners = new Set<(entry: OutboxEntry) => void>();

  constructor(
    // Not read directly: every write this service makes goes through `outbox`
    // and `applier`, which each hold their own `Database`. Kept as the first
    // constructor argument for symmetry with them and because a later task
    // (answer handling building on this one) may need it.
    _db: Database,
    private readonly transport: SyncTransport,
    private readonly outbox: Outbox,
    private readonly applier: PullApplier,
    private readonly options: PushServiceOptions,
  ) {}

  /** Asks for a push after the debounce window. Calling it again inside the window does not add a push. */
  schedule(): void {
    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void this.pushNow().catch((error) => console.error('[declarative-sqlite] push failed', error));
    }, this.options.debounceMs ?? 2000);
  }

  /** Pushes everything pending now, in batches, and returns the totals. Concurrent callers share one run. */
  async pushNow(): Promise<PushOutcome> {
    if (this.inFlight) return this.inFlight;
    this.inFlight = this.run().finally(() => {
      this.inFlight = undefined;
    });
    return this.inFlight;
  }

  private async run(): Promise<PushOutcome> {
    const outcome: PushOutcome = { applied: 0, noop: 0, rejected: 0, batches: 0 };
    this.setStatus({ sending: true });
    try {
      for (;;) {
        const batch = this.retryBatch ?? (await this.nextBatch());
        if (!batch) break;
        const sent = await this.sendBatch(batch);
        outcome.batches++;
        outcome.applied += sent.applied;
        outcome.noop += sent.noop;
        outcome.rejected += sent.rejected;
        if (!sent.delivered) break;
      }
    } finally {
      this.setStatus({ sending: false });
    }
    return outcome;
  }

  /**
   * Reads what's `pending`, groups it by `groupId` (one row's simultaneous
   * column changes, which must land in the same server call), and fills a
   * batch up to the cap without ever splitting a group across two batches —
   * a group larger than the cap cannot happen (`Outbox.record` refuses it).
   */
  private async nextBatch(): Promise<PreparedBatch | undefined> {
    const pending = await this.outbox.pending();
    if (pending.length === 0) return undefined;

    const cap = Math.min(this.options.maxChangesPerBatch ?? MAX_BATCH_CHANGES, MAX_BATCH_CHANGES);
    const groups = new Map<string, OutboxEntry[]>();
    for (const entry of pending) {
      const group = groups.get(entry.groupId);
      if (group) group.push(entry);
      else groups.set(entry.groupId, [entry]);
    }

    const entries: OutboxEntry[] = [];
    for (const group of groups.values()) {
      if (entries.length > 0 && entries.length + group.length > cap) break;
      entries.push(...group);
      if (entries.length >= cap) break;
    }

    const batchId = newBatchId();
    await this.outbox.markSending(
      entries.map((e) => e.id),
      batchId,
    );
    return { batchId, entries };
  }

  /**
   * Sends one prepared batch. A network error is handed to `handleFailure` and
   * reported as undelivered so `run()` stops rather than trying the next
   * batch out of order; a delivered answer clears the retry state, files the
   * per-change verdicts and the receipt rows, and notifies rejection
   * listeners for anything the server turned down.
   */
  private async sendBatch(batch: PreparedBatch): Promise<{ delivered: boolean; applied: number; noop: number; rejected: number }> {
    const changes: PushChange[] = batch.entries.map((entry) => ({
      table: toWireTable(entry.tableName),
      id: entry.systemId,
      column: toWireColumn(entry.columnName),
      old: entry.oldValue,
      new: entry.newValue,
      changedAt: entry.changedAt,
    }));
    const payload: PushBatch = { batchId: batch.batchId, deviceId: this.options.deviceId, changes };

    let answer;
    try {
      answer = await this.transport.push(payload);
    } catch (error) {
      await this.handleFailure(batch, error);
      return { delivered: false, applied: 0, noop: 0, rejected: 0 };
    }

    this.retryBatch = undefined;
    this.setStatus({ attempt: 0, nextRetryAt: null, lastError: null, online: true });

    await this.outbox.applyResults(
      batch.batchId,
      answer.results,
      batch.entries.map((e) => e.id),
    );
    await this.applyAnswerRows(batch, answer.rows);

    const counts = { applied: 0, noop: 0, rejected: 0 };
    const rejectedIds: string[] = [];
    for (const result of answer.results) {
      counts[result.result]++;
      if (result.result === 'rejected') {
        const entry = batch.entries[result.index];
        if (entry) rejectedIds.push(entry.id);
      }
    }
    await this.notifyRejected(rejectedIds);
    return { delivered: true, ...counts };
  }

  /**
   * Tells `rejectedListeners` about exactly the entries the caller just
   * marked rejected — never the whole rejected backlog. `Outbox` has no
   * by-id lookup (and this file does not add one), so the only way to get
   * current `OutboxEntry` records is to read every `rejected` row and keep
   * the ones named in `rejectedIds`; an unrelated entry left over from an
   * earlier, still-unresolved rejection is excluded because its id was
   * never passed in. Both `sendBatch` (one rejected batch answer) and
   * `handleFailure` (a whole batch refused outright) fan out through this
   * one place instead of each re-implementing the same filter-and-notify.
   */
  private async notifyRejected(rejectedIds: string[]): Promise<void> {
    if (rejectedIds.length === 0 || this.rejectedListeners.size === 0) return;
    const wanted = new Set(rejectedIds);
    for (const entry of await this.outbox.entries({ status: 'rejected' })) {
      if (!wanted.has(entry.id)) continue;
      for (const listener of [...this.rejectedListeners]) listener(entry);
    }
  }

  /** Applies the answer rows table by table, with the seq guard, and without moving any cursor. Rows the batch did not mention are ignored. */
  private async applyAnswerRows(batch: PreparedBatch, rows: RowDoc[]): Promise<void> {
    if (rows.length === 0) return;
    const tableOf = new Map<string, string>();
    for (const entry of batch.entries) tableOf.set(entry.systemId, entry.tableName);

    const byTable = new Map<string, RowDoc[]>();
    for (const row of rows) {
      const table = tableOf.get(row.id);
      if (!table) continue;
      const bucket = byTable.get(table);
      if (bucket) bucket.push(row);
      else byTable.set(table, [row]);
    }
    for (const [table, tableRows] of byTable) {
      await this.applier.applyRows(table, tableRows, { seqGuard: true, advanceCursor: false });
    }
  }

  /**
   * A network error means the server never reached a verdict: the entries go
   * back to `pending` (same batch id kept on the row) so the next attempt
   * resends the identical batch id and the server answers idempotently. A
   * terminal error (a 4xx `isTerminalError` recognises) is different — the
   * server did see the batch and refused it, so it is filed as rejected
   * rather than retried forever.
   */
  private async handleFailure(batch: PreparedBatch, error: unknown): Promise<void> {
    const message = error instanceof Error ? error.message : String(error);
    await this.outbox.resetSending(batch.batchId);

    if (this.options.isTerminalError?.(error)) {
      this.retryBatch = undefined;
      await this.outbox.applyResults(
        batch.batchId,
        batch.entries.map((_, index) => ({ index, result: 'rejected' as const, error: message })),
        batch.entries.map((e) => e.id),
      );
      await this.notifyRejected(batch.entries.map((e) => e.id));
      this.setStatus({ lastError: message });
      return;
    }

    this.retryBatch = batch;
    const backoff = this.options.backoffMs ?? [5000, 30000, 120000];
    const attempt = this.state.attempt + 1;
    const delay = backoff[Math.min(attempt - 1, backoff.length - 1)] ?? 120000;
    this.setStatus({ attempt, online: false, lastError: message, nextRetryAt: Date.now() + delay });

    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void this.pushNow().catch(() => undefined);
    }, delay);
  }

  /** The app reports connectivity came back: retry immediately instead of waiting out the backoff. */
  notifyOnline(): void {
    this.setStatus({ online: true, nextRetryAt: null });
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    void this.pushNow().catch(() => undefined);
  }

  /** The current status snapshot, for a component that reads it once rather than subscribing. */
  status(): SyncStatus {
    return this.state;
  }

  /** Subscribes to every status change (sending, backoff, connectivity). Returns an unsubscribe function. */
  onStatusChange(listener: (status: SyncStatus) => void): () => void {
    this.statusListeners.add(listener);
    return () => {
      this.statusListeners.delete(listener);
    };
  }

  /** Subscribes to entries the server rejected, so the UI can surface them without polling. Returns an unsubscribe function. */
  onRejected(listener: (entry: OutboxEntry) => void): () => void {
    this.rejectedListeners.add(listener);
    return () => {
      this.rejectedListeners.delete(listener);
    };
  }

  /** Cancels any scheduled push. Called when the database closes. */
  stop(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
  }

  private setStatus(patch: Partial<SyncStatus>): void {
    this.state = { ...this.state, ...patch };
    for (const listener of [...this.statusListeners]) listener(this.state);
  }
}
