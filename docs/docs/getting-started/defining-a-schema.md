---
sidebar_position: 2
---

# Defining a Schema

The schema is the blueprint for your database. In `declarative_sqlite`, you define your entire schema—including tables, columns, keys, and views—using a fluent Dart API. This declarative approach makes your schema easy to read, manage, and version control.

## The Schema Builder Function

Everything starts with a schema builder function. This is a top-level function that takes a `SchemaBuilder` instance and uses it to define the database structure.

Let's create a file for our schema definition.

```dart title="lib/database/schema.dart"
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Defines the database schema for the application.
void buildAppSchema(SchemaBuilder builder) {
  // Table definitions will go here
}
```

## Defining Tables

You define a table using the `builder.table()` method. It takes the table name and a callback where you define the table's columns and keys.

### Column Types

The library provides methods for all standard SQLite column types:
- `text(name)`
- `integer(name)`
- `real(name)`: for floating-point numbers
- `date(name)`: stored as an ISO 8601 string
- `guid(name)`: for UUIDs
- `fileset(name)`: a special type for managing collections of files

### Column Constraints

Each column builder provides methods to add constraints:
- `.notNull()`: Makes the column required.
- `.defaultValue(value)`: Sets a default value for the column.
- `.min(value)` / `.max(value)`: Adds validation constraints (for `integer` and `real` types).

### Keys and Indexes

You can define primary keys, unique constraints, and indexes using the `table.key()` method.
- `key([...]).primary()`: Defines a primary key.
- `key([...]).unique()`: Defines a unique constraint.
- `key([...]).indexed()`: Creates an index on the specified columns.

### Example: A Simple Schema

Let's define a schema for a simple to-do list application with `users` and `tasks` tables.

```dart title="lib/database/schema.dart"
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:uuid/uuid.dart';

void buildAppSchema(SchemaBuilder builder) {
  // Users table
  builder.table('users', (table) {
    table.guid('id');
    table.text('name');
    table.text('email');
    table.date('created_at');

    // Define a primary key on the 'id' column
    table.key(['id']).primary();
    // Add a unique index on the 'email' column
    table.key(['email']).unique();
  });

  // Tasks table
  builder.table('tasks', (table) {
    table.guid('id');
    table.guid('user_id');
    table.text('title');
    table.text('description');
    table.integer('is_completed'); // 0 for false, 1 for true
    table.date('due_date');

    // Define primary key
    table.key(['id']).primary();
    // Add an index on user_id for faster lookups
    table.key(['user_id']).indexed();
  });
}
```

## Usage in Your Application

Once you've defined your schema function, you'll use it when opening the database:

```dart
final schemaBuilder = SchemaBuilder();
buildAppSchema(schemaBuilder);
final schema = schemaBuilder.build();

final database = await DeclarativeDatabase.open(
  'app.db',
  databaseFactory: databaseFactoryFfi,
  schema: schema,
  fileRepository: FilesystemFileRepository('files'),
);
```

## Next Steps

Now that you have a schema, the next step is to initialize the database.

- **Next**: [Initializing the Database](./initializing-the-database.md)
