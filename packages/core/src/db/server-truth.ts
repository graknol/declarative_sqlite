import { quoteIdentifier } from './sql';
import type { Database } from './database';
import type { Transaction } from './transaction';
import { rowScope, writeRow } from './tables';
import type { Row } from '../types';

const SERVER_WRITE = Symbol('declarative-sqlite:server-write');

/**
 * The token that unlocks writing to `.synced()` tables. It is minted inside the
 * sync runtime and is not exported from the package entry point, so application
 * code cannot obtain one — server truth changes only when the pull applier or
 * the outbox committer says so.
 */
export interface ServerWriteCapability {
  readonly [SERVER_WRITE]: true;
}

/** Mints the capability object that unlocks `serverWriter`. Called once by `src/sync/runtime.ts`; never exported from the package entry. */
export function createServerWriteCapability(): ServerWriteCapability {
  return { [SERVER_WRITE]: true };
}

/** The write methods `db.tables` withholds from synced tables. Every method takes an open transaction, so a pull page is one commit and one invalidation. */
export interface ServerWriter {
  upsert(tx: Transaction, table: string, row: Row): Promise<void>;
  setColumns(tx: Transaction, table: string, key: string, values: Row): Promise<void>;
  delete(tx: Transaction, table: string, key: string): Promise<number>;
}

/**
 * Hands out the server-truth write path for a database, in exchange for a
 * capability only the sync runtime holds. Throws if the capability is forged.
 */
export function serverWriter(db: Database, capability: ServerWriteCapability): ServerWriter {
  if (!capability || capability[SERVER_WRITE] !== true) {
    throw new Error('serverWriter requires the sync runtime capability object');
  }

  return {
    async upsert(tx, table, row) {
      const def = db.tableDef(table);
      const keyColumn = db.keyColumn(table);
      const key = String(row[keyColumn] ?? '');
      if (!key) throw new Error(`${table}: cannot upsert a row without ${keyColumn}`);
      await writeRow(tx, def, keyColumn, key, row, 'upsert');
    },

    async setColumns(tx, table, key, values) {
      const def = db.tableDef(table);
      await writeRow(tx, def, db.keyColumn(table), key, values, 'update');
    },

    async delete(tx, table, key) {
      const def = db.tableDef(table);
      const keyColumn = db.keyColumn(table);
      const scopeColumns = def.synced?.scope ?? [];
      const existing =
        scopeColumns.length > 0
          ? await tx.queryOne<Row>(
              `SELECT ${scopeColumns.map(quoteIdentifier).join(', ')} FROM ${quoteIdentifier(table)} WHERE ${quoteIdentifier(keyColumn)} = ?`,
              [key],
            )
          : undefined;
      const result = await tx.execute(`DELETE FROM ${quoteIdentifier(table)} WHERE ${quoteIdentifier(keyColumn)} = ?`, [key]);
      tx.markWritten(table, key, existing ? rowScope(def, existing) : null);
      return result.changes;
    },
  };
}
