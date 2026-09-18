/**
 * `declarative-sqlite/react` — the thin React binding. Everything here is a view
 * over the primitives in the root entry point; nothing in this file holds state
 * of its own, because drafts, the outbox and live queries already live in the
 * library where a component unmount cannot lose them.
 */
export { SyncProvider, useDatabase, useSyncRuntime } from './provider';
export type { SyncProviderProps } from './provider';
export { useLiveQuery } from './use-live-query';
export { useDraftField } from './use-draft-field';
export type { DraftFieldBinding } from './use-draft-field';
