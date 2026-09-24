---
title: Migrations
description: "Automatic, additive schema migration on open, and when a table rebuild is needed."
---

# Migrations

There are no migration files. Each time `Database.open` runs, it compares your
schema with the database on disk and applies the difference, all in one
transaction: the migration either completes or leaves the database as it was.

## What happens automatically

| Change in your schema | What the migration does |
|---|---|
| New table | `CREATE TABLE` with its indexes |
| New column | `ALTER TABLE … ADD COLUMN`. A `notNull` column gets its default in existing rows |
| New or changed index / unique key | Creates it; an index with the same name but different columns or type is dropped and recreated |
| Table or column removed from the schema | **Nothing.** Data stays; the plan reports it as extra |

Migrations only ever add. An older build of your app that opens a newer
database still works, and no user data is dropped because a line was deleted
from the schema.

## Changes that rebuild a table

SQLite can't change these in place:

- a column's storage type (e.g. `text` to `integer`)
- a column switching between nullable and `notNull`
- the primary key

Doing any of these requires copying the table into a new one. By default
`Database.open` refuses and throws `MigrationBlockedError`, which lists the
tables involved. To allow it:

```ts
const db = await Database.open({ schema, adapter, allowRecreate: true });
```

The rebuild copies every row, including columns the schema no longer declares.
When a column becomes `notNull`, existing `NULL`s get the declared default.

## Options

```ts
const db = await Database.open({
  schema,
  adapter,
  migrate: 'auto',        // 'auto' (default) | 'plan' | 'off'
  allowRecreate: false,
  onMigrationPlan: (plan) => {
    if (plan.hasOperations) console.info('Migrating', plan.operations.map((o) => o.description));
  },
});
```

- `auto`: migrate on open.
- `plan`: work out the operations and call `onMigrationPlan`, but don't run
  anything.
- `off`: skip migration and assume the database already matches.

`onMigrationPlan` is called before anything runs. It's a good place to log
what your users' databases are doing.

## Planning without opening

```ts
import { planMigration } from 'declarative-sqlite';

await adapter.open();
const plan = await planMigration(adapter, schema);
plan.diff.extraTables;   // tables in the database but not the schema
plan.diff.extraColumns;  // same, for columns
plan.operations;         // [{ description, sql: [...] }]
```
