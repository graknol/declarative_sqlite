# Declarative SQLite for Flutter

Flutter-specific widgets and utilities to easily integrate the `declarative_sqlite` core library into your Flutter applications.

This package provides helpful widgets that simplify state management and UI updates when working with a reactive SQLite database.

## Features

- **`DatabaseProvider`**: An `InheritedWidget` that manages the lifecycle of your `DeclarativeDatabase` instance and provides easy access to it from anywhere in the widget tree.
- **`QueryListView`**: A reactive `ListView` that listens to a streaming query and automatically rebuilds itself with smooth animations when the underlying data changes. It handles all the boilerplate of subscribing to a stream and updating the UI.

## Getting Started

Add the packages to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  declarative_sqlite: ^1.0.1
  declarative_sqlite_flutter: ^1.0.1
  sqflite: ^2.3.3 # The standard SQLite plugin for Flutter
```

### Example Usage

```dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

// 1. Define your schema (can be in a separate file)
void buildSchema(SchemaBuilder builder) {
  builder.table('tasks', (table) {
    table.guid('id').notNull();
    table.text('title').notNull();
    table.integer('completed').notNull().defaultValue(0);
    table.key(['id']).primary();
  });
}

// 2. Wrap your app with DatabaseProvider
void main() {
  runApp(
    DatabaseProvider(
      databaseName: 'tasks.db',
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
      title: 'Task Manager',
      home: TaskScreen(),
    );
  }
}

// 3. Use QueryListView to display reactive data
class TaskScreen extends StatelessWidget {
  const TaskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final database = DatabaseProvider.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: QueryListView(
        database: database,
        query: (q) => q.from('tasks').orderBy('title'),
        itemBuilder: (context, record) {
          final isCompleted = record.data['completed'] == 1;
          return ListTile(
            title: Text(
              record.data['title'] as String,
              style: TextStyle(
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
            onTap: () {
              // Toggle completion status
              database.update(
                'tasks',
                {'completed': isCompleted ? 0 : 1},
                where: 'id = ?',
                whereArgs: [record.data['id']],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add a new task
          database.insert('tasks', {
            'id': Uuid().v4(),
            'title': 'New Task at ${DateTime.now().toIso8601String()}',
          });
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

For more detailed examples and API documentation, please refer to our [**official documentation**](https://graknol.github.io/declarative_sqlite/docs/flutter-integration/intro).
