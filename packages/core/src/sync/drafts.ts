import type { Database } from '../db/database';
import { toSqlValue } from '../db/tables';
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

  constructor(
    protected readonly db: Database,
    protected readonly outbox: Outbox,
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
