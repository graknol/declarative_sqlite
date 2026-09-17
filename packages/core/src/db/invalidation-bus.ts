import type { ScopeValues } from '../types';

/**
 * What changed in one table during one transaction: a map from row key to that
 * row's scope values, or `null` when the writer could not name the rows (a raw
 * `execute`, a bulk statement, a full refresh). `null` means every live query on
 * the table must re-run.
 */
export type TableInvalidation = ReadonlyMap<string, ScopeValues | null> | null;

/** One event per committed write transaction, naming every table it touched. There is deliberately no per-row event. */
export interface InvalidationEvent {
  tables: ReadonlyMap<string, TableInvalidation>;
}

/** Accumulates what a transaction wrote so that exactly one event can be emitted after it commits. */
export class WriteLog {
  private readonly rows = new Map<string, Map<string, ScopeValues | null>>();
  private readonly wholeTables = new Set<string>();

  markRow(table: string, rowKey: string, scope: ScopeValues | null = null): void {
    let forTable = this.rows.get(table);
    if (!forTable) {
      forTable = new Map();
      this.rows.set(table, forTable);
    }
    forTable.set(rowKey, scope);
  }

  markTable(table: string): void {
    this.wholeTables.add(table);
  }

  isEmpty(): boolean {
    return this.rows.size === 0 && this.wholeTables.size === 0;
  }

  toEvent(): InvalidationEvent {
    const tables = new Map<string, TableInvalidation>();
    for (const [table, rows] of this.rows) tables.set(table, rows);
    for (const table of this.wholeTables) tables.set(table, null);
    return { tables };
  }
}

/**
 * Delivers one invalidation event per committed transaction to everything that
 * cares (live queries, the outbox counters, the app). A listener that throws is
 * reported to the console and skipped: one broken subscriber must not stop the
 * rest of the UI from refreshing.
 */
export class InvalidationBus {
  private readonly listeners = new Set<(event: InvalidationEvent) => void>();

  subscribe(listener: (event: InvalidationEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  emit(event: InvalidationEvent): void {
    for (const listener of [...this.listeners]) {
      try {
        listener(event);
      } catch (error) {
        console.error('[declarative-sqlite] invalidation listener failed', error);
      }
    }
  }
}
