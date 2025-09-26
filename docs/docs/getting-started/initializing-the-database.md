---
sidebar_position: 3
---

# Initializing the Database

Once you have defined your schema, the next step is to create and initialize a `DeclarativeDatabase` instance. This process involves connecting to the database file, analyzing the existing schema, and automatically applying any necessary migrations.

## Using `DatabaseProvider` (Flutter)

In a Flutter application, the easiest way to manage the database lifecycle is with the `DatabaseProvider` widget. It handles initialization, closing the connection, and making the database instance available to the entire widget tree.

Wrap the root of your application (or a relevant subtree) with `DatabaseProvider`.

```dart title="lib/main.dart"
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'database/schema.dart'; // Your schema definition

void main() {
  runApp(
    DatabaseProvider(
      databaseName: 'app.db',
      schema: buildAppSchema,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomeScreen(),
    );
  }
}
```

### Accessing the Database

From any descendant widget, you can get the database instance using `DatabaseProvider.of(context)`.

```dart
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Get the database instance from the provider
    final database = DatabaseProvider.of(context);

    return Scaffold(
      // ...
    );
  }
}
```

## Manual Initialization (Standalone Dart)

In a standalone Dart application, you create and initialize the `DeclarativeDatabase` instance manually.

You'll need to provide:
- `path`: The path to the database file.
- `schema`: A reference to your schema builder function.
- `dbFactory`: The database factory from `sqflite_common_ffi`.

```dart title="bin/my_app.dart"
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'path/to/your/schema.dart';

Future<void> main() async {
  // 1. Initialize the FFI driver
  sqfliteFfiInit();

  // 2. Build the schema
  final schemaBuilder = SchemaBuilder();
  buildAppSchema(schemaBuilder);
  final schema = schemaBuilder.build();

  // 3. Open the database
  final database = await DeclarativeDatabase.open(
    'my_app.db',
    databaseFactory: databaseFactoryFfi,
    schema: schema,
    fileRepository: FilesystemFileRepository('files'),
  );

  print('Database opened successfully!');

  // Your application logic here...
  await database.insert('users', {
    'id': '1',
    'name': 'Alice',
    'email': 'alice@example.com',
  });

  // Query data
  final users = await database.queryMaps((q) => q.from('users'));
  print('Users: $users');

  // 4. Close the database when done
  await database.close();
}
```

## Automatic Migrations

The first time you initialize the database, `declarative_sqlite` will:
1. See that no tables exist.
2. Generate the `CREATE TABLE` and `CREATE VIEW` statements based on your schema.
3. Execute them to build the database from scratch.

On subsequent initializations, it will:
1. Introspect the live database schema.
2. Compare it to your declarative schema definition.
3. If there are differences (e.g., a new table, a modified column), it will generate and execute the necessary `ALTER TABLE`, `CREATE TABLE`, etc. scripts to migrate the database to the new schema.

This process is fully automatic. You only need to update your schema in your Dart code, and the library handles the rest.

## Debugging Migrations

You can enable detailed logging for the migration process by setting the `logStatements` flag to `true`. This is useful for debugging what happens during initialization.

**In Flutter:**
```dart
DatabaseProvider(
  databaseName: 'app.db',
  schema: appSchema,
  logStatements: true, // Enable logging
  child: const MyApp(),
)
```

**In Dart:**
```dart
final database = DeclarativeDatabase(
  path: 'my_app.db',
  schema: appSchema,
  dbFactory: dbFactory,
  logStatements: true, // Enable logging
);
await database.init();
```

## Next Steps

With your database initialized, you are now ready to perform CRUD operations and run queries.

- **Next**: [CRUD Operations](./crud-operations.md)
