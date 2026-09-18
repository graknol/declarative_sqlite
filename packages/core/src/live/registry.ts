import { DatabaseError } from '../db/database';
import type { InvalidationEvent } from '../db/invalidation-bus';
import type { Row, SqlValue } from '../types';
import { LiveQuery, type LiveQuerySpec, type RowTransform } from './live-query';

/**
 * Owns every open live query for one database and routes invalidation events to
 * the ones that care. One committed transaction produces one event, so a
 * 200-row pull page re-runs each affected query exactly once.
 */
export class LiveRegistry {
  private readonly queries = new Set<LiveQuery<never>>();
  private transform: RowTransform | undefined;

  constructor(
    private readonly runQuery: (sql: string, params: SqlValue[]) => Promise<Row[]>,
    subscribeToInvalidations: (listener: (event: InvalidationEvent) => void) => () => void,
  ) {
    subscribeToInvalidations((event) => this.onInvalidation(event));
  }

  /** Creates and starts a live query: it runs immediately and re-runs on every invalidation event that `matches()` it. Registered so `closeAll()` and `setRowTransform()` can reach it. */
  create<T extends Record<string, unknown>>(spec: LiveQuerySpec): LiveQuery<T> {
    const query = new LiveQuery<T>(
      spec,
      this.runQuery,
      () => this.transform,
      (closed) => this.queries.delete(closed),
    );
    this.queries.add(query as unknown as LiveQuery<never>);
    this.refreshInBackground(query as unknown as LiveQuery<never>);
    return query;
  }

  /** Installs the overlay + draft-hold transform. Called once by the sync runtime; passing `undefined` removes it. */
  setRowTransform(transform: RowTransform | undefined): void {
    this.transform = transform;
    for (const query of this.queries) this.refreshInBackground(query);
  }

  /** Closes every live query currently open on this registry. Called once, from `Database.close()`. */
  closeAll(): void {
    for (const query of [...this.queries]) query.close();
  }

  private onInvalidation(event: InvalidationEvent): void {
    for (const query of [...this.queries]) {
      if (query.matches(event)) this.refreshInBackground(query);
    }
  }

  /**
   * Runs `query.refresh()` from a fire-and-forget call site: a new query's first
   * run, a transform change, or a matching invalidation. None of these callers
   * can await it, and `Database.close()` marks the database closed before
   * draining the write queue a transaction was already sitting in, so a
   * `DatabaseError: Database is closed` here is an ordinary shutdown race — the
   * commit (and its invalidation event) already went through fine, only this
   * refresh lost the race — and is caught and logged instead of becoming an
   * unhandled rejection. Anything else re-throws so a genuine bug still
   * surfaces loudly.
   */
  private refreshInBackground(query: LiveQuery<never>): void {
    query.refresh().catch((error: unknown) => {
      if (error instanceof DatabaseError && error.message === 'Database is closed') {
        console.error('[declarative-sqlite] live query refresh failed', error);
        return;
      }
      throw error;
    });
  }
}
