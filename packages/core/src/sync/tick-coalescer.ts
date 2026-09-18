import type { ScopeValues } from '../types';
import type { CursorStore } from './cursor-store';
import type { PullService } from './pull-service';

/** One `TableChanged` notification: the table, the highest `SYNC_SEQ` the tick service has seen, and optionally the scope values that changed. */
export interface Tick {
  table: string;
  seq: number;
  scopes?: Array<string | number>;
}

/**
 * Turns a stream of notifications into as few pulls as possible. Ticks are
 * collected for about 1.5 seconds and then resolved together: for each table,
 * every scope the app has open is pulled once, skipping scopes whose cursor is
 * already at or past the tick's seq, and — when the tick lists the scopes that
 * changed — skipping the ones it does not mention. That is what stops a device
 * on another work order from pulling an empty page every time anyone saves.
 */
export class TickCoalescer {
  private pendingTicks = new Map<string, Tick>();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private stopped = false;

  constructor(
    private readonly pull: PullService,
    private readonly cursors: CursorStore,
    private readonly options: { windowMs?: number } = {},
  ) {}

  /** Schedules a pull for the table and scope(s) in the tick, coalescing with other pending ticks without pulling immediately. */
  notify(tick: Tick): void {
    if (this.stopped) return;
    const existing = this.pendingTicks.get(tick.table);
    if (existing) {
      const scopes = this.mergeScopes(existing.scopes, tick.scopes);
      const seq = Math.max(existing.seq, tick.seq);
      this.pendingTicks.set(tick.table, scopes ? { table: tick.table, seq, scopes } : { table: tick.table, seq });
    } else {
      this.pendingTicks.set(tick.table, { ...tick });
    }

    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void this.flush().catch((error) => console.error('[declarative-sqlite] tick pull failed', error));
    }, this.options.windowMs ?? 1500);
  }

  /** Resolves the collected ticks now. The Sync button calls this so the user does not wait out the window. */
  async flush(): Promise<void> {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    const ticks = [...this.pendingTicks.values()];
    this.pendingTicks.clear();

    for (const tick of ticks) {
      // `stopped` is checked once per tick (not just before the outer loop
      // begins) so a `stop()` racing in while an earlier tick's scopes are
      // still being pulled does not let this flush keep issuing pulls after
      // the runtime it belongs to has closed.
      if (this.stopped) return;
      for (const scope of this.pull.openScopes(tick.table)) {
        if (this.stopped) return;
        if (!this.tickCoversScope(tick, scope)) continue;
        const cursor = await this.cursors.get(tick.table, scope);
        if (this.stopped) return;
        if (cursor >= tick.seq) continue;
        await this.pull.pull(tick.table, scope, { from: 'window' });
      }
    }
  }

  /** Prevents any further scheduled or in-flight pulls from completing after this call. */
  stop(): void {
    this.stopped = true;
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    this.pendingTicks.clear();
  }

  private tickCoversScope(tick: Tick, scope?: ScopeValues): boolean {
    if (!tick.scopes || tick.scopes.length === 0) return true;
    if (!scope) return true;
    const values = Object.values(scope).map(String);
    return tick.scopes.some((value) => values.includes(String(value)));
  }

  /**
   * Combines the scopes of two ticks for the same table. An absent or empty
   * scopes list means "everything on this table changed", and that signal
   * must never be narrowed away by merging in a tick that names specific
   * scopes — broad beats narrow regardless of which side it came from.
   * Only when both ticks name scopes do the two lists merge (deduplicated).
   */
  private mergeScopes(
    a: Array<string | number> | undefined,
    b: Array<string | number> | undefined,
  ): Array<string | number> | undefined {
    if (!a || a.length === 0 || !b || b.length === 0) return undefined;
    return [...new Set([...a, ...b])];
  }
}
