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

  notify(tick: Tick): void {
    if (this.stopped) return;
    const existing = this.pendingTicks.get(tick.table);
    if (!existing || tick.seq > existing.seq) {
      this.pendingTicks.set(tick.table, {
        ...tick,
        ...(existing?.scopes && tick.scopes ? { scopes: [...new Set([...existing.scopes, ...tick.scopes])] } : {}),
      });
    } else if (existing.scopes && tick.scopes) {
      existing.scopes = [...new Set([...existing.scopes, ...tick.scopes])];
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
}
