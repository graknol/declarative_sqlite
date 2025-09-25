# Declarative SQLite (Core)

The foundation of the Declarative SQLite ecosystem. This package provides all the core functionality for declarative schema definition, data manipulation, streaming queries, and synchronization for Dart applications.

For Flutter-specific features, see [`declarative_sqlite_flutter`](../declarative_sqlite_flutter/).

## Features

- **Declarative Schema**: Define your database schema using a fluent, easy-to-read builder API. Your schema is your single source of truth.
- **Automatic Migrations**: The library automatically detects schema changes and generates and applies the necessary migration scripts. No more manual `ALTER TABLE` statements.
- **Type-Safe Queries**: Build complex SQL queries with type safety and autocompletion using a powerful query builder.
- **Streaming Queries**: Create reactive queries that automatically emit new results when underlying data changes, perfect for building responsive UIs.
- **Conflict-Free Sync**: Built-in support for data synchronization using a Hybrid Logical Clock (HLC). This enables conflict-free, last-write-wins data merging, essential for applications that work offline or have multiple data sources.
- **File Management**: Integrated support for attaching and managing files linked to database records, with garbage collection for orphaned files.

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  declarative_sqlite: ^1.0.1
  # For standalone Dart apps, you need a native library loader.
  sqflite_common_ffi: ^2.3.3
```

### Example Usage (Standalone Dart)

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

// 1. Define your database schema
void buildSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.integer('age');
    table.key(['id']).primary();
  });
}

Future<void> main() async {
  // 2. Initialize the FFI driver (optional, not for Android/iOS, only for desktop)
  sqfliteFfiInit();
  final dbFactory = databaseFactoryFfi;

  // 3. Create and initialize the database
  final database = DeclarativeDatabase(
    path: 'my_app.db',
    schema: buildSchema,
    dbFactory: dbFactory,
  );
  await database.init();

  // 4. Insert data
  await database.insert('users', {
    'id': 'a1b2c3d4',
    'name': 'Alice',
    'age': 30,
  });

  // 5. Query data
  final users = await database.query('users', where: 'age > ?', whereArgs: [25]);
  print('Users older than 25: $users');

  // 6. Use streaming queries
  final userStream = database.streamQuery('users');
  final subscription = userStream.listen((userList) {
    print('Current users: $userList');
  });

  // Changes will automatically be pushed to the stream
  await database.update(
    'users',
    {'age': 31},
    where: "name = 'Alice'",
  );

  // Clean up
  await subscription.cancel();
  await database.close();
}
```

For more detailed examples and API documentation, please refer to our [**official documentation**](https://graknol.github.io/declarative_sqlite/docs/core-library/intro).
