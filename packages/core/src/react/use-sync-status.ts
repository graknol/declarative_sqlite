import { useSyncExternalStore } from 'react';
import type { SyncStatus } from '../sync/push-service';
import { useSyncRuntime } from './provider';

const OFFLINE_UNKNOWN: SyncStatus = { online: true, sending: false, attempt: 0, nextRetryAt: null, lastError: null };

/**
 * The push service's current state: online, a push in flight, how many attempts
 * the current backoff has made and when the next one is due. Use it for the
 * header indicator and for an "offline, N changes waiting" line — the app owns
 * the Norwegian wording.
 */
export function useSyncStatus(): SyncStatus {
  const sync = useSyncRuntime();
  return useSyncExternalStore(
    (onStoreChange) => sync.push.onStatusChange(() => onStoreChange()),
    () => sync.push.status(),
    () => OFFLINE_UNKNOWN,
  );
}
