import type { InvalidationEvent } from '../db/invalidation-bus';
import { scopeMatches } from '../schema/scopes';
import type { Row, ScopeValues, SqlValue } from '../types';
import { diffRows } from './diff-rows';

/** One table a live query reads, and the scope of the rows it cares about. A dependency without a scope means the whole table. */
export interface ReadDependency {
  table: string;
  scope?: ScopeValues;
}

/** Everything a live query needs: the SQL to run, what it reads, and the column that identifies a row. */
export interface LiveQuerySpec {
  sql: string;
  params?: SqlValue[];
  reads: ReadDependency[];
  /** The column that identifies a row across emissions, almost always `system_id`. */
  key: string;
  /** Floor between emissions in milliseconds, for pathological writers. Coalescing per transaction usually makes this unnecessary. */
  minInterval?: number;
  /** The table whose overlay and draft holds apply to these rows. Defaults to the first read's table. */
  overlayTable?: string;
}

/** Applies the pending outbox overlay and the draft holds to rows before they are emitted. Installed by the sync runtime. */
export type RowTransform = (table: string, rows: Row[]) => Row[];

/**
 * A query that stays current. `matches()` is what keeps it quiet: the registry
 * only calls `refresh()` when a committed transaction wrote a row of one of its
 * `reads` tables inside its scope (or could not name the rows it touched at
 * all), so a write to an unrelated work order never costs this query a query
 * round-trip. Every run that is allowed to happen — the first one, a matching
 * invalidation, or a manual `refresh()` — passes its rows through the overlay
 * and draft-hold transform and emits to every subscriber, with unchanged rows
 * kept by reference (via `diffRows`) so a renderer keyed on identity does not
 * redraw them. A live query is created by `db.live(...)` and must be closed
 * when the view goes away.
 */
export class LiveQuery<T extends Record<string, unknown> = Row> {
  private rows: T[] = [];
  private listeners = new Set<(rows: T[]) => void>();
  private closed = false;
  /** The run currently querying the database, if any. Concurrent `refresh()` calls await this instead of starting a second query. */
  private inFlight: Promise<void> | undefined;
  /** At most one follow-up run, queued while `inFlight` was busy. Coalesces any number of invalidations that arrive mid-run into a single extra pass. */
  private queued: Promise<void> | undefined;
  private lastEmit = 0;
  private trailing: ReturnType<typeof setTimeout> | undefined;

  constructor(
    readonly spec: LiveQuerySpec,
    private readonly runQuery: (sql: string, params: SqlValue[]) => Promise<Row[]>,
    private readonly getTransform: () => RowTransform | undefined,
    private readonly onClose: (query: LiveQuery<never>) => void,
  ) {}

  /**
   * Registers a listener that receives every future emission, and delivers the
   * current rows immediately if the query has already produced a result. Returns
   * a function that unsubscribes it; call it when the consuming view goes away.
   */
  subscribe(listener: (rows: T[]) => void): () => void {
    this.listeners.add(listener);
    if (this.rows.length > 0) listener(this.rows);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /** The most recently emitted rows, or `[]` before the first result arrives. Does not trigger a query. */
  snapshot(): T[] {
    return this.rows;
  }

  /**
   * Re-runs the query and emits its (possibly unchanged) result to every
   * subscriber. Called by the registry on a matching invalidation, and by the
   * app for a manual refresh. A call made while a run is already in flight does
   * not start a second query: it is folded into one queued follow-up run, and
   * the returned promise settles only once that follow-up has actually
   * completed, so awaiting `refresh()` is a reliable way to wait for fresh data.
   */
  refresh(): Promise<void> {
    if (this.closed) return Promise.resolve();
    if (this.inFlight) {
      if (!this.queued) {
        this.queued = this.inFlight.then(() => {
          this.queued = undefined;
          return this.refresh();
        });
      }
      return this.queued;
    }
    const run = this.runOnce().finally(() => {
      this.inFlight = undefined;
    });
    this.inFlight = run;
    return run;
  }

  private async runOnce(): Promise<void> {
    const raw = await this.runQuery(this.spec.sql, this.spec.params ?? []);
    if (this.closed) return;
    const transform = this.getTransform();
    const table = this.spec.overlayTable ?? this.spec.reads[0]?.table;
    const transformed = transform && table ? transform(table, raw) : raw;
    const { rows } = diffRows(this.rows as unknown as Row[], transformed, this.spec.key);
    this.rows = rows as unknown as T[];
    this.emit();
  }

  /** True when this event wrote a row this query reads, inside this query's scope. An event with unnamed rows always matches. */
  matches(event: InvalidationEvent): boolean {
    for (const read of this.spec.reads) {
      if (!event.tables.has(read.table)) continue;
      const invalidation = event.tables.get(read.table);
      if (invalidation === null || invalidation === undefined) return true;
      for (const scope of invalidation.values()) {
        if (scopeMatches(scope, read.scope)) return true;
      }
    }
    return false;
  }

  /** Stops the query: clears its listeners, cancels any pending debounced emission, and removes it from its registry. Safe to call more than once. */
  close(): void {
    if (this.closed) return;
    this.closed = true;
    if (this.trailing) clearTimeout(this.trailing);
    this.listeners.clear();
    this.onClose(this as unknown as LiveQuery<never>);
  }

  private emit(): void {
    const minInterval = this.spec.minInterval ?? 0;
    const now = Date.now();
    if (minInterval > 0 && now - this.lastEmit < minInterval) {
      if (this.trailing) return;
      this.trailing = setTimeout(() => {
        this.trailing = undefined;
        this.lastEmit = Date.now();
        this.deliver();
      }, minInterval - (now - this.lastEmit));
      return;
    }
    this.lastEmit = now;
    this.deliver();
  }

  private deliver(): void {
    for (const listener of [...this.listeners]) {
      try {
        listener(this.rows);
      } catch (error) {
        console.error('[declarative-sqlite] live query listener failed', error);
      }
    }
  }
}
