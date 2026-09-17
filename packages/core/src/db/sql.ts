/** Quotes an identifier for SQLite by doubling embedded quotes. Every table and column name the library puts into SQL goes through this. */
export function quoteIdentifier(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}
