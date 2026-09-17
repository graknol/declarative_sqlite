import { buildLibraryTables, OUTBOX_TABLE, SYNC_CURSOR_TABLE } from './library-tables';
import { TableBuilder } from './table-builder';
import { SchemaError, type Schema, type SyncedDef } from './types';

/** What `schema.table(...)` returns: the one thing you may still say about the table you just declared. */
export interface TableHandle {
  /** Marks the table as server truth: names the column holding the server row key and the columns a pull may filter on. A synced table is writable only through the sync runtime. */
  synced(def: SyncedDef): void;
}

/**
 * Declares a database. The fluent shape is the one v2 had, so an existing
 * `schema.ts` carries over unchanged apart from dropping `.lww()` and adding
 * `.synced()`. `build()` appends the library's own tables (`outbox`,
 * `sync_cursor`) and returns an immutable `Schema` that `Database.open`
 * migrates towards.
 */
export class SchemaBuilder {
  private readonly builders: TableBuilder[] = [];
  private readonly names = new Set<string>();

  table(name: string, build: (t: TableBuilder) => void): TableHandle {
    if (name === OUTBOX_TABLE || name === SYNC_CURSOR_TABLE) {
      throw new SchemaError(`Table "${name}" is owned by declarative-sqlite and must not be declared by the application`);
    }
    if (this.names.has(name)) {
      throw new SchemaError(`Table "${name}" is declared twice`);
    }
    this.names.add(name);
    const builder = new TableBuilder(name);
    build(builder);
    this.builders.push(builder);
    return {
      synced: (def: SyncedDef) => builder.markSynced(def),
    };
  }

  build(): Schema {
    return { tables: [...this.builders.map((b) => b.build()), ...buildLibraryTables()] };
  }
}
