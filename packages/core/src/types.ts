/** A value SQLite can store and bind: text, number, null or a byte array. Booleans are coerced to 0/1 before they reach this type. */
export type SqlValue = string | number | null | Uint8Array;

/** One database row as a plain object, keyed by lowercase column name. Every read in the library produces rows of this shape before typing is layered on top. */
export type Row = Record<string, SqlValue>;

/** The values of a synced table's scope columns for one row, e.g. `{ wo_no: 3188 }`. Used to decide which live queries an invalidation touches and which cursor a pull belongs to. */
export type ScopeValues = Record<string, string | number>;
