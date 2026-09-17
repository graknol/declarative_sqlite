import type { PullRequest, PushBatch, PushResult, RowsPage } from './wire';

/**
 * The only thing the library needs from the network, supplied by the
 * application: fetch a page of rows after a cursor, and push a batch of column
 * changes. Implementations mirror `apply-work-api`'s `/sync/rows` and
 * `/sync/push`; the library never knows about HTTP, auth or retries at this
 * level — a rejected promise is a network error and triggers the push service's
 * backoff.
 */
export interface SyncTransport {
  pullRows(req: PullRequest): Promise<RowsPage>;
  push(batch: PushBatch): Promise<PushResult>;
}
