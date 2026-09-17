import type { SQLiteAdapter } from '../adapters/adapter';
import { quoteIdentifier } from '../db/sql';
import type { ColumnDef, KeyDef, LogicalType, Schema, StorageType, TableDef } from '../schema/types';

interface PragmaColumn {
  name: string;
  type: string;
  notnull: number;
  dflt_value: string | null;
  pk: number;
}

interface PragmaIndex {
  name: string;
  unique: number;
  origin: string;
}

interface PragmaIndexColumn {
  seqno: number;
  name: string;
}

function toStorageType(declared: string): StorageType {
  const type = declared.toUpperCase();
  if (type.includes('INT')) return 'INTEGER';
  if (type.includes('REAL') || type.includes('FLOA') || type.includes('DOUB')) return 'REAL';
  if (type.includes('BLOB')) return 'BLOB';
  return 'TEXT';
}

function toLogicalType(storage: StorageType): LogicalType {
  return storage === 'TEXT' ? 'text' : storage === 'INTEGER' ? 'integer' : storage === 'REAL' ? 'real' : 'blob';
}

function parseDefault(raw: string | null, storage: StorageType): string | number | undefined {
  if (raw === null) return undefined;
  if (storage === 'INTEGER' || storage === 'REAL') {
    const value = Number(raw);
    return Number.isNaN(value) ? undefined : value;
  }
  if (raw.startsWith("'") && raw.endsWith("'")) return raw.slice(1, -1).replace(/''/g, "'");
  return raw;
}

/**
 * Reads the database as it actually is — `sqlite_master` plus `PRAGMA
 * table_info` and `PRAGMA index_list`/`index_info` — into the same `Schema`
 * shape the builder produces, so the differ compares like with like. Logical
 * types are lost in the database (a date is TEXT), so introspected columns
 * carry the logical type their storage implies; the differ only ever compares
 * storage.
 */
export async function introspect(adapter: SQLiteAdapter): Promise<Schema> {
  const tableRows = await adapter.all<{ name: string }>(
    `SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name`,
  );

  const tables: TableDef[] = [];
  for (const { name } of tableRows) {
    const quoted = quoteIdentifier(name);
    const pragmaColumns = await adapter.all<PragmaColumn>(`PRAGMA table_info(${quoted})`);

    const columns: ColumnDef[] = pragmaColumns.map((row) => {
      const type = toStorageType(row.type);
      const column: ColumnDef = { name: row.name, type, logical: toLogicalType(type), notNull: row.notnull === 1 };
      const defaultValue = parseDefault(row.dflt_value, type);
      if (defaultValue !== undefined) column.defaultValue = defaultValue;
      return column;
    });

    const keys: KeyDef[] = [];
    const pkColumns = pragmaColumns
      .filter((row) => row.pk > 0)
      .sort((a, b) => a.pk - b.pk)
      .map((row) => row.name);
    if (pkColumns.length > 0) keys.push({ columns: pkColumns, type: 'PRIMARY' });

    const indexes = await adapter.all<PragmaIndex>(`PRAGMA index_list(${quoted})`);
    for (const index of indexes) {
      if (index.origin === 'pk') continue;
      const indexColumns = await adapter.all<PragmaIndexColumn>(`PRAGMA index_info(${quoteIdentifier(index.name)})`);
      keys.push({
        columns: indexColumns.sort((a, b) => a.seqno - b.seqno).map((c) => c.name),
        type: index.unique === 1 ? 'UNIQUE' : 'INDEX',
        name: index.name,
      });
    }

    tables.push({ name, columns, keys, library: false });
  }

  return { tables };
}
