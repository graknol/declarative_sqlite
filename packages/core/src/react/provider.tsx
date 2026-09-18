import { createContext, useContext, useEffect, type ReactNode } from 'react';
import type { Database } from '../db/database';
import type { SyncRuntime } from '../sync/runtime';

interface SyncContextValue {
  db: Database;
  sync: SyncRuntime;
}

const SyncContext = createContext<SyncContextValue | undefined>(undefined);

export interface SyncProviderProps {
  db: Database;
  sync: SyncRuntime;
  /**
   * A value that changes whenever the user navigates — `location.pathname` in a
   * router. Changing it ends every open draft, which is one of the exit paths
   * the draft lifecycle requires.
   */
  routeKey?: string;
  children: ReactNode;
}

/**
 * Puts the database and the sync runtime in context and owns the global draft
 * exit paths: `pagehide` and `visibilitychange` end every open draft, so
 * backgrounding the app on an iPad commits what the user typed instead of
 * losing it, and so does a route change when `routeKey` is supplied.
 */
export function SyncProvider({ db, sync, routeKey, children }: SyncProviderProps): JSX.Element {
  useEffect(() => {
    const endAll = () => {
      void sync.drafts.endAll();
    };
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') endAll();
    };
    window.addEventListener('pagehide', endAll);
    document.addEventListener('visibilitychange', onVisibility);
    return () => {
      window.removeEventListener('pagehide', endAll);
      document.removeEventListener('visibilitychange', onVisibility);
    };
  }, [sync]);

  useEffect(() => {
    return () => {
      void sync.drafts.endAll();
    };
  }, [sync, routeKey]);

  return <SyncContext.Provider value={{ db, sync }}>{children}</SyncContext.Provider>;
}

/** The database from the nearest `SyncProvider`. Throws with a readable message when there is none. */
export function useDatabase(): Database {
  const value = useContext(SyncContext);
  if (!value) throw new Error('useDatabase must be used inside a <SyncProvider>');
  return value.db;
}

/** The sync runtime from the nearest `SyncProvider`. Throws with a readable message when there is none. */
export function useSyncRuntime(): SyncRuntime {
  const value = useContext(SyncContext);
  if (!value) throw new Error('useSyncRuntime must be used inside a <SyncProvider>');
  return value.sync;
}
