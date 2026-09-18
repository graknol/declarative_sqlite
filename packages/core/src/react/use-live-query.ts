import { useCallback, useRef, useSyncExternalStore, type MutableRefObject } from 'react';
import type { LiveQuery, LiveQuerySpec } from '../live/live-query';
import { useDatabase } from './provider';
import type { Database } from '../db/database';

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

interface CurrentQuery<T extends Record<string, unknown>> {
  key: string;
  query: LiveQuery<T>;
}

/**
 * Returns the `LiveQuery` for the current spec, creating it if the ref is
 * empty or was created for a different spec. This is deliberately the ONLY
 * place a query is created, and it never closes the query it replaces —
 * `subscribe`'s cleanup owns closing. That split matters for React 18
 * `<StrictMode>`: `getSnapshot` and `subscribe` are each called twice in a
 * row (mount, cleanup, mount) and must be safe to run that way, which is
 * only possible if creation reads from and writes to a ref shared by both,
 * instead of a `useMemo` cache that outlives any single `subscribe` cycle.
 */
function getOrCreateQuery<T extends Record<string, unknown>>(
  ref: MutableRefObject<CurrentQuery<T> | null>,
  db: Database,
  spec: LiveQuerySpec,
  key: string,
): LiveQuery<T> {
  const current = ref.current;
  if (current && current.key === key) return current.query;
  const query = db.live<T>(spec);
  ref.current = { key, query };
  return query;
}

/**
 * Subscribes a component to a live query through `useSyncExternalStore`. The
 * query is created from the spec and re-created only when its content
 * changes (compared by value, not by object identity, since a spec is almost
 * always a fresh literal on every render), so a parent re-render costs
 * nothing. `LiveQuery` already guarantees exactly one emission per genuine
 * change and reference-stable rows for anything that did not change, so this
 * hook adds no diffing of its own — it only relays what the query hands back.
 * The query that a given `subscribe` call created is the one it closes when
 * its cleanup runs, which is what makes the whole hook safe under React 18
 * `<StrictMode>`'s mount/cleanup/mount cycle: a throwaway subscription closes
 * only the instance it made, and the mount that survives ends up subscribed
 * to a fresh, unclosed query rather than one an earlier cleanup already
 * killed.
 */
export function useLiveQuery<T extends Record<string, unknown>>(spec: LiveQuerySpec): T[] {
  const db = useDatabase();
  const key = specKey(spec);
  const ref = useRef<CurrentQuery<T> | null>(null);
  // `spec` is intentionally omitted from both dependency arrays below, exactly
  // as the old `useMemo(() => db.live<T>(spec), [db, key])` omitted it: a spec
  // is normally a fresh object literal every render, but `key` already
  // captures everything about it that matters, so depending on `key` alone is
  // what keeps `subscribe` and `getSnapshot` stable across renders that carry
  // an equivalent spec. Without that stability, React's internal effect for
  // `useSyncExternalStore` (keyed on `subscribe`'s identity) would tear down
  // and rebuild on every render, which — now that teardown really closes the
  // query — would close and recreate it in a loop.

  const subscribe = useCallback(
    (onStoreChange: () => void) => {
      const query = getOrCreateQuery(ref, db, spec, key);
      const unsubscribe = query.subscribe(() => onStoreChange());
      return () => {
        unsubscribe();
        query.close();
        if (ref.current?.query === query) ref.current = null;
      };
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [db, key],
  );

  const getSnapshot = useCallback(
    () => getOrCreateQuery(ref, db, spec, key).snapshot(),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [db, key],
  );

  return useSyncExternalStore(subscribe, getSnapshot, () => EMPTY as unknown as T[]);
}
