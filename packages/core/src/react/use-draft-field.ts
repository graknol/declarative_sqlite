import { useCallback, useSyncExternalStore, type ChangeEvent, type KeyboardEvent } from 'react';
import type { SyncRuntime } from '../sync/runtime';
import { useSyncRuntime } from './provider';

/** Everything an input needs. Spread it onto the element; do not keep a `useState` beside it. */
export interface DraftFieldBinding<T> {
  value: T;
  isDrafting: boolean;
  isPending: boolean;
  onFocus(): void;
  onChange(next: T | ChangeEvent<HTMLInputElement>): void;
  onBlur(): void;
  onKeyDown(event: KeyboardEvent): void;
}

interface DraftSnapshot<T> {
  isDrafting: boolean;
  draftValue: T | undefined;
  isPending: boolean;
}

/**
 * The reactive half of `useDraftField`: whether a draft is open, what it holds,
 * and whether the column has an unconfirmed outbox entry. Each `useSyncExternalStore`
 * call subscribes and unsubscribes a single listener that `Drafts`/`Outbox` keep in
 * a plain `Set` — nothing is created or torn down by the act of subscribing, so
 * there is no resource for React 18 `<StrictMode>`'s mount/cleanup/mount cycle to
 * kill out from under the surviving mount: the throwaway mount's listener is added
 * and then removed, and the real mount adds its own, independent of the first.
 */
function useDraftSnapshot<T>(sync: SyncRuntime, table: string, systemId: string, column: string): DraftSnapshot<T> {
  const isDrafting = useSyncExternalStore(
    (onStoreChange) => sync.drafts.subscribe(onStoreChange),
    () => sync.drafts.isActive(table, systemId, column),
    () => false,
  );

  const draftValue = useSyncExternalStore(
    (onStoreChange) => sync.drafts.subscribe(onStoreChange),
    () => sync.drafts.get(table, systemId, column) as T | undefined,
    () => undefined,
  );

  const isPending = useSyncExternalStore(
    (onStoreChange) => sync.outbox.subscribe(onStoreChange),
    () => sync.outbox.pendingColumns(table, systemId).has(column),
    () => false,
  );

  return { isDrafting, draftValue, isPending };
}

/** Pulls the typed value out of a raw `T` or the `ChangeEvent` an `<input>`'s `onChange` hands over. */
function extractValue<T>(next: T | ChangeEvent<HTMLInputElement>): T {
  if (next !== null && typeof next === 'object' && 'target' in next) {
    return (next as ChangeEvent<HTMLInputElement>).target.value as unknown as T;
  }
  return next;
}

/** Ends the draft on blur or Enter — a changed value goes to the outbox, an unchanged one just releases the column. */
function commitDraft(sync: SyncRuntime, table: string, systemId: string, column: string): void {
  void sync.drafts.end(table, systemId, column);
}

/**
 * Ends the draft on Escape by first setting it back to the value it was seeded
 * with, so `end()` sees no change and takes the "unchanged" branch — releasing
 * the column and applying any held server value — with no special case needed
 * in the draft store itself.
 */
function abandonDraft<T>(sync: SyncRuntime, table: string, systemId: string, column: string, seedValue: T): void {
  sync.drafts.set(table, systemId, column, seedValue);
  void sync.drafts.end(table, systemId, column);
}

/**
 * Binds one editable column of one row. The draft lives in the library's store,
 * keyed `(table, systemId, column)`, so the input can unmount and remount — a
 * virtualised list, a re-render from a pull — without losing a keystroke. Focus
 * starts the draft, every keystroke updates it, and blur, Enter, an explicit
 * save, the Sync button, a route change or `pagehide` end it: changed values go
 * to the outbox and the pending overlay takes the column over, unchanged ones
 * release it and let any held server value through. Escape abandons the draft.
 * `currentValue` is what the live query emitted for this cell — already
 * overlaid and already held — and is what the field shows when no draft is open.
 */
export function useDraftField<T>(table: string, systemId: string, column: string, currentValue: T): DraftFieldBinding<T> {
  const sync = useSyncRuntime();
  const { isDrafting, draftValue, isPending } = useDraftSnapshot<T>(sync, table, systemId, column);

  const onFocus = useCallback(() => {
    sync.drafts.begin(table, systemId, column, currentValue);
  }, [sync, table, systemId, column, currentValue]);

  const onChange = useCallback(
    (next: T | ChangeEvent<HTMLInputElement>) => {
      const value = extractValue(next);
      if (!sync.drafts.isActive(table, systemId, column)) sync.drafts.begin(table, systemId, column, currentValue);
      sync.drafts.set(table, systemId, column, value);
    },
    [sync, table, systemId, column, currentValue],
  );

  const onBlur = useCallback(() => commitDraft(sync, table, systemId, column), [sync, table, systemId, column]);

  const onKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (event.key === 'Enter') commitDraft(sync, table, systemId, column);
      else if (event.key === 'Escape') abandonDraft(sync, table, systemId, column, currentValue);
    },
    [sync, table, systemId, column, currentValue],
  );

  return {
    value: isDrafting ? (draftValue as T) : currentValue,
    isDrafting,
    isPending,
    onFocus,
    onChange,
    onBlur,
    onKeyDown,
  };
}
