import type { ScopeValues } from '../types';
import type { Schema } from './types';

/** Thrown when a scope cannot be expressed on the wire: too many pairs, an empty value, or a comma the format has no escape for. */
export class ScopeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ScopeError';
  }
}

const MAX_SCOPE_PAIRS = 4;

/**
 * Renders scope values as the server spells them: `COLUMN:value[,COLUMN:value]`,
 * uppercase column names, at most four pairs, sorted by column so the same scope
 * always produces the same cursor key. Returns `undefined` for no scope, which
 * means a full-table pull. Throws `ScopeError` for anything the server would
 * reject with `CSCOPEFMT` / `CSCOPECNT`.
 */
export function formatScope(scope?: ScopeValues): string | undefined {
  if (!scope) return undefined;
  const entries = Object.entries(scope);
  if (entries.length === 0) return undefined;
  if (entries.length > MAX_SCOPE_PAIRS) {
    throw new ScopeError(`A scope may name at most four columns, got ${entries.length}`);
  }
  return entries
    .map(([column, value]) => {
      const text = String(value).trim();
      if (text.length === 0) throw new ScopeError(`Scope column ${column} has an empty value`);
      if (text.includes(',')) throw new ScopeError(`Scope column ${column} value contains a comma, which the wire format cannot escape`);
      return [column.toUpperCase(), text] as const;
    })
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([column, value]) => `${column}:${value}`)
    .join(',');
}

/** Parses a wire scope string back into lowercase column values. Values come back as strings; callers that need numbers coerce them. */
export function parseScope(text: string): ScopeValues {
  const scope: ScopeValues = {};
  for (const pair of text.split(',')) {
    const separator = pair.indexOf(':');
    if (separator <= 0) throw new ScopeError(`Scope element "${pair}" is not COLUMN:value`);
    scope[pair.slice(0, separator).trim().toLowerCase()] = pair.slice(separator + 1).trim();
  }
  return scope;
}

/** The key a cursor is stored under: the local table name, a pipe, and the wire scope (or `*` for a full-table pull). */
export function scopeKey(table: string, scope?: ScopeValues): string {
  return `${table}|${formatScope(scope) ?? '*'}`;
}

/**
 * Decides whether a written row is inside a live query's scope. A row whose
 * scope values are unknown (`null`, e.g. a raw `execute` that reported no scope)
 * matches everything, because the safe answer to "might this have changed my
 * rows" is yes. A query with no scope also matches everything on its table.
 */
export function scopeMatches(rowScope: ScopeValues | null, queryScope: ScopeValues | undefined): boolean {
  if (rowScope === null) return true;
  if (!queryScope) return true;
  for (const [column, value] of Object.entries(queryScope)) {
    if (String(rowScope[column] ?? '') !== String(value)) return false;
  }
  return true;
}

/** The server's `IS_SCOPE` registry, keyed by uppercase table name with uppercase column names. */
export type ScopeAllowList = Record<string, string[]>;

/**
 * Optional startup check (off by default, see the plan's Global Constraints):
 * confirms every `.synced()` scope column is one the server will actually accept,
 * so a typo surfaces as a thrown error at boot instead of as `CBADSCOPE` on the
 * first pull. Call it once with the list fetched from the API.
 */
export function validateScopes(schema: Schema, allowList: ScopeAllowList): void {
  for (const table of schema.tables) {
    if (!table.synced) continue;
    const wireTable = table.name.toUpperCase();
    const allowed = new Set((allowList[wireTable] ?? []).map((c) => c.toUpperCase()));
    for (const column of table.synced.scope) {
      if (!allowed.has(column.toUpperCase())) {
        throw new ScopeError(`${wireTable}: scope column ${column.toUpperCase()} is not flagged IS_SCOPE on the server`);
      }
    }
  }
}
