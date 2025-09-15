# Declarative SQLite Migrations

This document explains how to use the automatic migration feature of `declarative_sqlite`.

## How it Works

The migration system compares your declarative schema (defined in code) with the live schema of the database and generates the necessary SQL scripts to bring the database up to date.

The process is as follows:

1.  **Introspect**: The library reads the schema of the live database (`PRAGMA table_info`, `PRAGMA index_list`, etc.).
2.  **Diff**: It compares the live schema with your declarative schema and identifies the differences.
3.  **Generate Scripts**: It generates a list of SQL statements to resolve these differences.
4.  **Execute**: The scripts are executed within a single transaction to ensure atomicity.

## Usage

The migration logic is typically run when you open the database. Here's a simplified example:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/migration/diff_schemas.dart';
import 'package:declarative_sqlite/src/migration/generate_migration_scripts.dart';
import 'package:declarative_sqlite/src/migration/introspect_schema.dart';
import 'package:sqflite/sqflite.dart';

Future<void> main() async {
  final db = await openDatabase('my_app.db');

  // 1. Define your declarative schema
  final schemaBuilder = SchemaBuilder();
  schemaBuilder.table('users', (table) {
    table.guid('id').notNull('some_default_id');
    table.text('name').notNull('Default Name');
    table.integer('age').notNull(0);
    table.key(['id']).primary();
  });
  final declarativeSchema = schemaBuilder.build();

  // 2. Introspect the live database schema
  final liveSchema = await introspectSchema(db);

  // 3. Diff the schemas to get a list of changes
  final changes = diffSchemas(declarativeSchema, liveSchema);

  // 4. Generate the migration scripts
  final scripts = generateMigrationScripts(changes);

  // 5. Execute the scripts in a transaction
  await db.transaction((txn) async {
    for (final script in scripts) {
      await txn.execute(script);
    }
  });

  await db.close();
}
```

## Supported Migrations

The migration system currently supports the following changes:

- **Tables**:
  - `CREATE TABLE`
  - `DROP TABLE`
- **Columns**:
  - `ADD COLUMN`
  - `DROP COLUMN` (recreates the table)
- **Constraints**:
  - Adding or removing a `NOT NULL` constraint (recreates the table).
  - When adding a `NOT NULL` constraint, you **must** provide a default value in your schema definition, which will be used to populate any existing `NULL` values.
- **Keys**:
  - Adding or removing a `PRIMARY KEY` or `INDEX` (recreates the table).
- **Views**:
  - `CREATE VIEW`
  - `DROP VIEW`
  - `ALTER VIEW` (drops and recreates the view)

## Table Recreation

For any operation that SQLite's `ALTER TABLE` does not support, the library will automatically and safely recreate the table. This includes:

- Dropping a column.
- Altering a column's constraints (e.g., adding `NOT NULL`).
- Adding or dropping a `PRIMARY KEY`.

The process is as follows to ensure data is not lost:

1.  The existing table is renamed to `old_<table_name>`.
2.  A new table is created with the correct schema and the original name.
3.  Data is copied from the `old_` table to the new table using an `INSERT INTO ... SELECT` statement.
    - If a `NOT NULL` constraint is being added, the provided default value will be used for any existing `NULL`s via the `IFNULL()` SQL function.
4.  The `old_` table is dropped.

This entire process is executed within a single transaction. If any step fails, the transaction is rolled back, and the database is left in its original state.
