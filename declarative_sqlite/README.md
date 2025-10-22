# Declarative SQLite (Core)

The foundation of the Declarative SQLite ecosystem. This package provides all the core functionality for declarative schema definition, data manipulation, and streaming queries for Dart applications.

For Flutter-specific features, see [`declarative_sqlite_flutter`](../declarative_sqlite_flutter/).

## Features

- **Declarative Schema**: Define your database schema using a fluent, easy-to-read builder API. Your schema is your single source of truth.
- **Automatic Migrations**: The library automatically detects schema changes and generates and applies the necessary migration scripts. No more manual `ALTER TABLE` statements.
- **Type-Safe Queries**: Build complex SQL queries with type safety and autocompletion using a powerful query builder.
- **Streaming Queries**: Create reactive queries that automatically emit new results when underlying data changes, perfect for building responsive UIs.
- **Reactive Synchronization**: Stream-based dirty row notifications enable efficient, real-time sync with external systems without polling.
- **LWW Columns**: Built-in support for Last-Writer-Wins (LWW) columns using Hybrid Logical Clock (HLC) timestamps for conflict resolution.
- **File Management**: Integrated support for attaching and managing files linked to database records, with garbage collection for orphaned files.

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  # Core library
  declarative_sqlite: ^1.4.0
  # Flutter integration package
  declarative_sqlite_flutter: ^1.4.0
  # Standard SQLite plugin for Flutter (Android/iOS)
  sqflite: ^2.3.3
```

### Example Usage (Flutter)

```dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

// 1. Define your database schema
void buildSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id');
    table.text('name');
    table.integer('age');
    table.key(['id']).primary();
  });
}

void main() {
  runApp(
    // 2. Wrap your app with DatabaseProvider
    DatabaseProvider(
      databaseName: 'my_app.db',
      schema: buildSchema,
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 3. Access the database from any descendant widget
    final database = DatabaseProvider.of(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Declarative SQLite Demo')),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              // 4. Insert data
              await database.insert('users', {
                'id': 'a1b2c3d4',
                'name': 'Alice',
                'age': 30,
              });
            },
            child: const Text('Add User'),
          ),
          // 5. Use QueryListView for reactive data display
          Expanded(
            child: QueryListView<DbRecord>(
              query: (q) => q.from('users').where('age').isGreaterThan(25),
              mapper: (row, db) => DbRecord(row, 'users', db),
              itemBuilder: (context, user) {
                return ListTile(
                  title: Text(user.getValue('name')!),
                  subtitle: Text('Age: ${user.getValue('age')}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

## Reactive Synchronization (New in 1.4.0)

The library now includes built-in reactive synchronization capabilities, eliminating the need for polling:

```dart
// Set up reactive sync when your app starts
database.onDirtyRowAdded?.listen((dirtyRow) {
  print('Data changed: ${dirtyRow.tableName} - ${dirtyRow.rowId}');
  
  // Trigger your sync logic immediately
  syncService.performSync();
});

// Your data changes are now instantly detected
await database.insert('users', {'name': 'Alice'}); // Triggers sync
await database.update('users', {'age': 30}, where: '...'); // Triggers sync
```

**Benefits:**
- ⚡ **Immediate sync** - no polling delays
- 🔋 **Better battery life** - no unnecessary checks
- 🎯 **Zero overhead** when no changes occur
- 🌐 **Perfect for offline-first apps**

For more detailed examples and API documentation, please refer to our [**official documentation**](https://graknol.github.io/declarative_sqlite/docs/core-library/intro).
