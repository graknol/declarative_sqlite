import { useEffect, useMemo, useSyncExternalStore } from 'react';
import type { LiveQuerySpec } from '../live/live-query';
import { useDatabase } from './provider';

const EMPTY: never[] = [];

/**
 * A stable key for a `LiveQuerySpec`, so the hook below re-creates the
 * underlying `LiveQuery` only when the SQL, its parameters, the declared
 * reads or the key column actually change — not on every render, where the
 * spec is typically a fresh object literal.
 */
function specKey(spec: LiveQuerySpec): string {
  return `${spec.sql}|${JSON.stringify(spec.params ?? [])}|${JSON.stringify(spec.reads)}|${spec.key}|${spec.minInterval ?? ''}|${spec.overlayTable ?? ''}`;
}

/**
 * Subscribes a component to a live query through `useSyncExternalStore`. The
 * query is created from the spec and re-created only when its content
 * changes (compared by value, not by object identity, since a spec is almost
 * always a fresh literal on every render), so a parent re-render costs
 * nothing. `LiveQuery` already guarantees exactly one emission per genuine
 * change and reference-stable rows for anything that did not change, so this
 * hook adds no diffing of its own — it only relays what the query hands back.
 * The query is closed when the component unmounts or the spec changes,
 * before the replacement subscribes, so no subscription from a stale render
 * ever outlives it.
 */
export function useLiveQuery<T extends Record<string, unknown>>(spec: LiveQuerySpec): T[] {
  const db = useDatabase();
  const key = specKey(spec);

  const query = useMemo(() => db.live<T>(spec), [db, key]);

  useEffect(() => {
    return () => {
      query.close();
    };
  }, [query]);

  return useSyncExternalStore(
    (onStoreChange) => query.subscribe(() => onStoreChange()),
    () => query.snapshot(),
    () => EMPTY as unknown as T[],
  );
}
