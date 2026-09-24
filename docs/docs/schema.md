---
title: Schema
description: "Declare tables, column types, defaults, keys and synced tables with SchemaBuilder."
---

# Schema

A schema is built once, in code, with `SchemaBuilder`. `schema.build()`
returns a frozen description that `Database.open` migrates the database to.

```ts
import { SchemaBuilder } from 'declarative-sqlite';

const schema = new SchemaBuilder();

schema.table('setting', (t) => {
  t.text('name').notNull('');
  t.text('value');
  t.key('name').unique();
});

schema
  .table('task', (t) => {
    t.integer('project_id').notNull(0);
    t.text('title').notNull('').maxLength(200);
    t.real('hours');
    t.date('due');
    t.key('project_id').index();
  })
  .synced({ key: 'system_id', scope: ['project_id'] });

export const appSchema = schema.build();
```

Table and column names are lowercase by convention. The sync layer
uppercases them on the wire and lowercases what comes back.

## Column types

| Builder | Stored as | Notes |
|---|---|---|
| `t.text(name)` | `TEXT` | |
| `t.integer(name)` | `INTEGER` | Booleans are written as `1` / `0` |
| `t.real(name)` | `REAL` | |
| `t.date(name)` | `TEXT` | Store ISO 8601 strings |
| `t.guid(name)` | `TEXT` | |
| `t.blob(name)` | `BLOB` | `Uint8Array` values |

Columns are nullable unless you call `.notNull(default)`. The default is
required: it's the value existing rows get when a migration adds the column to
a table that already holds data. It must match the column type (a number for
`integer`/`real`, a string for text types, a `Uint8Array` for `blob`).

`.maxLength(n)` is stored in the schema for your forms to read. Neither SQLite
nor the library enforces it.

## Keys and indexes

`t.key(...columns)` declares a key, then one of:

- `.primary()`: the table's primary key.
- `.unique(name?)`: a unique index. Named `uq_<table>_<columns>` if you don't
  pass a name.
- `.index(name?)`: a plain index, the default. Named `idx_<table>_<columns>` if
  you don't pass a name.

If you declare no primary key, the table's key column becomes the primary key:
`system_id` for a plain table, or the `.synced()` key for a synced one.

## Columns added for you

Every table you declare gets these columns unless you declare them yourself:

| Column | Type | Meaning |
|---|---|---|
| `system_id` | `TEXT NOT NULL DEFAULT ''` | Row id. The primary key unless you declare another |
| `system_removed` | `INTEGER NOT NULL DEFAULT 0` | Tombstone flag |
| `sync_seq` | `INTEGER NOT NULL DEFAULT 0` | Synced tables only: the server sequence number of the row's last change |

The library also adds two tables of its own to every schema, `outbox` and
`sync_cursor`. Don't declare tables with those names; `SchemaBuilder` throws a
`SchemaError` if you do.

## Synced tables

`.synced({ key, scope })` marks a table as a copy of server data:

- `key`: the column holding the server's row id. Almost always `system_id`.
- `scope`: the columns a pull can filter on, such as `['project_id']`. One pull
  can filter on at most four of them. Use `[]` if you always pull the whole
  table.

Both columns must be declared (or be `system_id`), or `build()` throws.

A synced table is read-only through `db.tables`: its API has only `get`. To
change it, record the change in the outbox with `sync.outbox.record`; see
[Sync](./sync.md).

### Checking scope columns against the server

If your server publishes which columns it accepts as scopes, you can check the
schema at startup and fail early instead of on the first pull:

```ts
import { validateScopes } from 'declarative-sqlite';

validateScopes(appSchema, { TASK: ['PROJECT_ID'] }); // throws ScopeError on a mismatch
```

## Errors

`SchemaError` is thrown while building, and names the table or column at fault:
a table or column declared twice, a reserved table name, a `.notNull` default of
the wrong type, or a synced key or scope column that isn't declared.
