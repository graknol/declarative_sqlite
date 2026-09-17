import type { Database } from '../db/database';
import { toSqlValue } from '../db/tables';
import type { ServerWriter } from '../db/server-truth';
import type { Row } from '../types';
import type { Outbox } from './outbox';

/** One drafted column: what is in the input now, what it was seeded with, and anything the server said while the user was typing. */
export interface DraftState {
  value: unknown;
  seed: unknown;
  heldServerValue?: { value: unknown };
  heldTombstone?: boolean;
}

/**
 * The third owner of state: what is being typed right now. A `(table, systemId,
 * column)` becomes a draft on focus and stops being one on blur, Enter, save,
 * Sync, a route change or `pagehide`. While it is a draft the column is held at
 * the drafted value no matter what a pull writes underneath, and a tombstone for
 * the row is held too — the rest of the row keeps updating live. Drafts live
 * here, never in a component, so a virtualised list can unmount the row without
 * losing a keystroke.
 */
export class Drafts {
  protected readonly drafts = new Map<string, Map<string, DraftState>>();
  private readonly listeners = new Set<() => void>();
  /**
   * Row keys with a tombstone held that has not yet applied. A column's own
   * `heldTombstone` flag is lost the moment that column's draft ends, so a row
   * with several open drafts needs this to remember the hold past the first
   * column to end — otherwise a draft begun on the row after `holdTombstone`
   * was called, then ended last, would find its own flag unset and skip the
   * delete even though the row was tombstoned and every draft on it is now over.
   */
  private readonly tombstoned = new Set<string>();

  constructor(
    protected readonly db: Database,
    protected readonly outbox: Outbox,
    private readonly writer: ServerWriter,
  ) {}

  protected static rowKey(table: string, systemId: string): string {
    return `${table}|${systemId}`;
  }

  /** Registers a listener called after every draft begins, changes or is otherwise touched. Returns an unsubscribe function. */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /** Starts a draft for one column, seeded with the value the input showed at the moment of focus. A draft already open for this column keeps its existing value: focus does not reset an in-progress edit. */
  begin(table: string, systemId: string, column: string, seedValue: unknown): void {
    const key = Drafts.rowKey(table, systemId);
    let columns = this.drafts.get(key);
    if (!columns) {
      columns = new Map();
      this.drafts.set(key, columns);
    }
    if (!columns.has(column)) columns.set(column, { value: seedValue, seed: seedValue });
    this.notify();
  }

  /** Records a keystroke: updates the value held for an already-open draft. Does nothing if the column has no draft (e.g. it was already ended). */
  set(table: string, systemId: string, column: string, value: unknown): void {
    const state = this.drafts.get(Drafts.rowKey(table, systemId))?.get(column);
    if (!state) return;
    state.value = value;
    this.notify();
  }

  /** The current drafted value for a column, or `undefined` if it is not being drafted. */
  get(table: string, systemId: string, column: string): unknown {
    return this.drafts.get(Drafts.rowKey(table, systemId))?.get(column)?.value;
  }

  /** Whether this column of this row currently has an open draft. */
  isActive(table: string, systemId: string, column: string): boolean {
    return this.drafts.get(Drafts.rowKey(table, systemId))?.has(column) ?? false;
  }

  /** The set of columns of this row that currently have an open draft. Empty when the row has none. */
  activeColumns(table: string, systemId: string): ReadonlySet<string> {
    return new Set(this.drafts.get(Drafts.rowKey(table, systemId))?.keys() ?? []);
  }

  /** Applies the holds to rows on their way to a subscriber: drafted columns keep the drafted value; everything else passes through. Rows with no draft, and calls when nothing is drafted anywhere, return the same array so reference-equality callers are not defeated by a no-op pass. */
  apply(table: string, rows: Row[]): Row[] {
    if (this.drafts.size === 0) return rows;
    const def = this.db.schema.tables.find((t) => t.name === table);
    const keyColumn = def?.synced?.key ?? 'system_id';

    let changed = false;
    const result = rows.map((row) => {
      const columns = this.drafts.get(Drafts.rowKey(table, String(row[keyColumn] ?? '')));
      if (!columns || columns.size === 0) return row;
      const held: Row = { ...row };
      for (const [column, state] of columns) {
        if (!(column in row)) continue;
        held[column] = toSqlValue(state.value);
      }
      changed = true;
      return held;
    });

    return changed ? result : rows;
  }

  /**
   * Offers a server value for a column. If that column is being typed, the value
   * is held until the draft ends and `true` is returned, so the pull applier
   * knows not to write it; otherwise nothing happens and `false` is returned.
   */
  holdServerValue(table: string, systemId: string, column: string, value: unknown): boolean {
    const state = this.drafts.get(Drafts.rowKey(table, systemId))?.get(column);
    if (!state) return false;
    state.heldServerValue = { value };
    return true;
  }

  /** Offers a tombstone for a row. Held while any column of the row is being typed, so the row cannot vanish under the user's fingers. */
  holdTombstone(table: string, systemId: string): boolean {
    const key = Drafts.rowKey(table, systemId);
    const columns = this.drafts.get(key);
    if (!columns || columns.size === 0) return false;
    for (const state of columns.values()) state.heldTombstone = true;
    this.tombstoned.add(key);
    return true;
  }

  /** Whether this row currently has any open draft — the guard that decides whether a held tombstone must keep waiting rather than apply. */
  hasHolds(table: string, systemId: string): boolean {
    const columns = this.drafts.get(Drafts.rowKey(table, systemId));
    return columns !== undefined && columns.size > 0;
  }

  /**
   * Writes what one column's exit implies — a changed value to the outbox, or a
   * held server value once nothing else is pending for it — without touching
   * `this.drafts` or `this.tombstoned`. Shared by `end()`, which wraps a single
   * call in its own transaction, and `endRow()`, which wraps a whole row's
   * calls in one shared transaction so they commit or roll back together.
   * `outbox.record` and the nested `this.db.transaction` for a held server
   * value each join whichever transaction is already open on this database, so
   * calling this from inside an outer `this.db.transaction` body never opens a
   * second, separately-committing transaction.
   */
  private async writeColumnExit(table: string, systemId: string, column: string, state: DraftState): Promise<'committed' | 'released'> {
    const changed = !Object.is(state.value, state.seed);
    if (changed) {
      await this.outbox.record({ table, systemId, changes: { [column]: state.value } });
    } else if (state.heldServerValue) {
      await this.db.transaction(async (tx) => {
        await this.writer.setColumns(tx, table, systemId, { [column]: toSqlValue(state.heldServerValue?.value) });
      });
    }
    return changed ? 'committed' : 'released';
  }

  /**
   * Ends one draft — blur, Enter, save, Sync, route change or `pagehide`. A
   * changed value is committed to SQLite and the outbox in one transaction and
   * the overlay takes the column over, which supersedes any server value held
   * for it. An unchanged value releases the column and applies the held server
   * value, if there is one. A held tombstone applies last, after the commit, so
   * the change is in the queue when the push answers `CNOROW` for it. The
   * in-memory draft is only removed once its write has committed without
   * throwing — a rejected write (an over-wide value, a batch cap) leaves the
   * draft exactly as the user left it, ready to retry.
   */
  async end(table: string, systemId: string, column: string): Promise<'committed' | 'released'> {
    const key = Drafts.rowKey(table, systemId);
    const columns = this.drafts.get(key);
    const state = columns?.get(column);
    if (!columns || !state) return 'released';

    const result = await this.db.transaction(() => this.writeColumnExit(table, systemId, column, state));

    columns.delete(column);
    if (columns.size === 0) this.drafts.delete(key);

    if (state.heldTombstone) this.tombstoned.add(key);
    if (this.tombstoned.has(key) && !this.hasHolds(table, systemId)) {
      this.tombstoned.delete(key);
      await this.db.transaction(async (tx) => {
        await this.writer.delete(tx, table, systemId);
      });
    }

    this.notify();
    return result;
  }

  /**
   * Ends every draft on one row in one shared transaction, so the row's exit is
   * all-or-nothing: if a later column's write throws, every earlier column's
   * write in this call rolls back with it, and no draft is removed from memory
   * for any column — the whole row is left exactly as it was, ready to retry.
   * `this.drafts` and `this.tombstoned` are only touched after the transaction
   * resolves; nothing about them is mutated while it can still fail.
   */
  async endRow(table: string, systemId: string): Promise<void> {
    const key = Drafts.rowKey(table, systemId);
    const columns = this.drafts.get(key);
    if (!columns || columns.size === 0) return;

    const active = [...columns.entries()];
    await this.db.transaction(async () => {
      for (const [column, state] of active) {
        await this.writeColumnExit(table, systemId, column, state);
      }
      if (this.tombstoned.has(key)) {
        await this.db.transaction(async (tx) => {
          await this.writer.delete(tx, table, systemId);
        });
      }
    });

    for (const [column] of active) columns.delete(column);
    const stillOpen = columns.size > 0;
    if (!stillOpen) this.drafts.delete(key);
    if (this.tombstoned.has(key) && !stillOpen) this.tombstoned.delete(key);

    this.notify();
  }

  /** Ends every open draft. The exit paths — Sync button, route change, `pagehide`, `visibilitychange` — call this. */
  async endAll(): Promise<void> {
    for (const key of [...this.drafts.keys()]) {
      const [table, systemId] = key.split('|');
      if (table === undefined || systemId === undefined) continue;
      await this.endRow(table, systemId);
    }
  }

  protected notify(): void {
    for (const listener of [...this.listeners]) {
      try {
        listener();
      } catch (error) {
        console.error('[declarative-sqlite] draft listener failed', error);
      }
    }
  }
}
