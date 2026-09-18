import { formatScope, scopeKey } from '../schema/scopes';
import type { ScopeValues } from '../types';
import type { CursorStore } from './cursor-store';
import type { PullApplier } from './pull-applier';
import type { SyncTransport } from './transport';
import { PULL_WINDOW, toWireTable } from './wire';

/** Where a pull starts: at the stored cursor, a window behind it (tick-driven), or at zero (manual refresh). */
export interface PullOptions {
  from?: 'cursor' | 'window' | 0;
  limit?: number;
  /** Safety valve against a server that always says `hasMore`. Default 100. */
  maxPages?: number;
}

/** What one `pull()` call did: how many rows it wrote, how many pages it fetched, and where the cursor landed. */
export interface PullReport {
  rows: number;
  pages: number;
  cursor: number;
}

/**
 * Fetches pages for one `(table, scope)` and hands them to the applier. A pull
 * the client makes because a tick said something changed starts a window behind
 * its cursor (`max(0, cursor − 1000)`), because `SYNC_SEQ` is assigned in draw
 * order and not in commit order, so a row can commit behind a cursor that has
 * already moved past it. A manual refresh reads the scope whole from zero.
 * Re-seeing a row costs nothing: every apply is an idempotent upsert by id.
 */
export class PullService {
  private readonly open = new Map<string, { table: string; scope?: ScopeValues; count: number }>();

  constructor(
    private readonly transport: SyncTransport,
    private readonly applier: PullApplier,
    private readonly cursors: CursorStore,
    private readonly options: { window?: number; pageLimit?: number } = {},
  ) {}

  /**
   * Pages through `GET /sync/rows` for one `(table, scope)` starting from the
   * point `options.from` selects, applying each page as it arrives and
   * following `hasMore` until the server says the scope is exhausted or
   * `maxPages` is reached. Returns how many rows were written, how many pages
   * that took, and the cursor the scope ended at.
   */
  async pull(table: string, scope?: ScopeValues, options: PullOptions = {}): Promise<PullReport> {
    const from = options.from ?? 'cursor';
    const cursor = await this.cursors.get(table, scope);
    const window = this.options.window ?? PULL_WINDOW;
    let after = from === 0 ? 0 : from === 'window' ? Math.max(0, cursor - window) : cursor;

    // Only an explicit override is sent on the wire; leaving `limit` unset lets
    // the transport fall back to its own default (the server's DEFAULT_PAGE_LIMIT
    // in production, or a test's configured page size), rather than this service
    // silently overriding a smaller size a caller relies on for control.
    const limit = options.limit ?? this.options.pageLimit;
    const maxPages = options.maxPages ?? 100;

    let rows = 0;
    let pages = 0;
    for (;;) {
      const wireScope = formatScope(scope);
      const page = await this.transport.pullRows({
        table: toWireTable(table),
        ...(wireScope ? { scope: wireScope } : {}),
        after,
        ...(limit !== undefined ? { limit } : {}),
      });
      pages++;
      rows += page.rows.length;
      await this.applier.applyPage(table, page, { ...(scope ? { scope } : {}), advanceCursor: true });
      after = page.next;
      if (!page.hasMore || pages >= maxPages) break;
    }

    return { rows, pages, cursor: await this.cursors.get(table, scope) };
  }

  /** Tells the service that a view is showing this scope, so tick-driven pulls know what to refresh. Returns the deregistration function. */
  registerScope(table: string, scope?: ScopeValues): () => void {
    const key = scopeKey(table, scope);
    const existing = this.open.get(key);
    if (existing) existing.count++;
    else this.open.set(key, { table, ...(scope ? { scope } : {}), count: 1 });
    return () => {
      const entry = this.open.get(key);
      if (!entry) return;
      entry.count--;
      if (entry.count <= 0) this.open.delete(key);
    };
  }

  /** The scopes currently registered as open for a table, one entry per distinct scope regardless of how many registrants share it. */
  openScopes(table: string): Array<ScopeValues | undefined> {
    return [...this.open.values()].filter((entry) => entry.table === table).map((entry) => entry.scope);
  }
}
