import { useEffect, useState } from 'react';
import { useSyncRuntime } from './provider';

/** What the header badge shows: recorded but unsent, in flight, and refused by the server. */
export interface OutboxCounts {
  pending: number;
  sending: number;
  rejected: number;
}

const ZERO: OutboxCounts = { pending: 0, sending: 0, rejected: 0 };

/**
 * Follows the outbox counters for a badge. Counting is a query, so this hook
 * keeps state rather than reading a snapshot synchronously: it recounts whenever
 * the outbox changes and drops the result if the component has unmounted.
 */
export function useOutboxCounts(): OutboxCounts {
  const sync = useSyncRuntime();
  const [counts, setCounts] = useState<OutboxCounts>(ZERO);

  useEffect(() => {
    let alive = true;
    const refresh = () => {
      void sync.outbox.counts().then((next) => {
        if (alive) setCounts(next);
      });
    };
    refresh();
    const stop = sync.outbox.subscribe(refresh);
    return () => {
      alive = false;
      stop();
    };
  }, [sync]);

  return counts;
}
