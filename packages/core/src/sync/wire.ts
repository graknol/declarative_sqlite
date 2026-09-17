import { toSqlValue } from '../db/tables';
import type { TableDef } from '../schema/types';
import type { Row } from '../types';

/** One row as the server sends it: system values beside a `data` object of business columns. */
export interface RowDoc {
  id: string;
  seq: number;
  removed: boolean;
  data: Record<string, unknown>;
}

/** One page of `GET /sync/rows`. `next` is the highest `seq` in the page (or the requested cursor when the page is empty). */
export interface RowsPage {
  table: string;
  rows: RowDoc[];
  next: number;
  hasMore: boolean;
}

/** What the transport needs to fetch a page: the wire table name, the formatted scope, the cursor and a page size. */
export interface PullRequest {
  table: string;
  scope?: string;
  after: number;
  limit?: number;
}

/** One column change as `POST /sync/push` carries it. `old` and `new` are JSON scalars, not strings; `changedAt` is informational. */
export interface PushChange {
  table: string;
  id: string;
  column: string;
  old: unknown;
  new: unknown;
  changedAt: string;
}

/** One push. The server stores the answer under `batchId`, so re-sending the same id returns the stored answer and applies nothing. */
export interface PushBatch {
  batchId: string;
  deviceId: string;
  changes: PushChange[];
}

export type PushResultCode = 'applied' | 'noop' | 'rejected';

/** The verdict on one change, by its zero-based position in the batch. */
export interface PushChangeResult {
  index: number;
  result: PushResultCode;
  error?: string | null;
}

/** The push answer: one result per change plus the current server state of every row the batch touched. The rows are a receipt, not a read — see `PullApplier`'s seq guard. */
export interface PushResult {
  batchId: string;
  results: PushChangeResult[];
  rows: RowDoc[];
}

/** `C_WORK_SYNC_LOG.OLD_VALUE`/`NEW_VALUE` are VARCHAR2(4000); a longer JSON scalar fails the call before the implementation runs. */
export const MAX_VALUE_CHARS = 4000;
/** The push cap. A change group larger than this cannot be pushed atomically and is a programming error. */
export const MAX_BATCH_CHANGES = 500;
/** `C_WORK_SYNC_BATCH.BATCH_ID` is VARCHAR2(36); a longer id fails the whole call and stores nothing, so the call is not even idempotent. */
export const MAX_BATCH_ID_CHARS = 36;
/** How far a tick-driven pull rewinds behind its cursor, because sequence order is not commit order. */
export const PULL_WINDOW = 1000;
/** The server's default page size; its maximum is 1000. */
export const DEFAULT_PAGE_LIMIT = 500;

/** Thrown before a push when a value is wider than the server column can hold. Terminal for that value; a shorter one may be recorded as a new change. */
export class ValueTooLongError extends Error {
  constructor(
    readonly table: string,
    readonly column: string,
    readonly length: number,
  ) {
    super(`${table}.${column}: value is ${length} characters, the server accepts at most ${MAX_VALUE_CHARS}`);
    this.name = 'ValueTooLongError';
  }
}

/** JSON-encodes a scalar for the outbox and the log. `undefined` becomes `null`, which is how a column is cleared. */
export function encodeScalar(value: unknown): string {
  return JSON.stringify(value ?? null);
}

/** Reverses `encodeScalar`. A stored value that is not valid JSON comes back as the raw string, so one corrupt row cannot break the queue. */
export function decodeScalar(text: string | null): unknown {
  if (text === null || text === undefined) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

export function assertScalarFits(table: string, column: string, encoded: string): void {
  if (encoded.length > MAX_VALUE_CHARS) throw new ValueTooLongError(table, column, encoded.length);
}

/** A batch id that fits `VARCHAR2(36)`: a v4 UUID is exactly 36 characters. */
export function newBatchId(): string {
  return crypto.randomUUID();
}

export function toWireTable(table: string): string {
  return table.toUpperCase();
}

export function toWireColumn(column: string): string {
  return column.toUpperCase();
}

/**
 * Turns a server `data` object into a local row: uppercase keys become
 * lowercase, values are coerced to something SQLite can bind, and columns the
 * schema does not declare are dropped — the server may know columns this client
 * does not, and that must never fail a pull.
 */
export function fromWireData(table: TableDef, data: Record<string, unknown>): Row {
  const declared = new Set(table.columns.map((c) => c.name));
  const row: Row = {};
  for (const [key, value] of Object.entries(data)) {
    const column = key.toLowerCase();
    if (!declared.has(column)) continue;
    row[column] = toSqlValue(value);
  }
  return row;
}
