# DeclarativeSQLite Flutter

Flutter integration for DeclarativeSQLite, providing reactive widgets for database operations.

## Features

- **`DatabaseProvider`**: Provides database context to widget tree and manages database lifecycle
- **`QueryListView`**: Reactive list widget that updates automatically when database changes
- **Stream integration**: Works with DeclarativeDatabase streaming queries
- **Automatic lifecycle management**: Handles database opening/closing

## Installation

Add both packages to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  declarative_sqlite: ^1.0.0
  declarative_sqlite_flutter: ^1.0.0
```

### Example Usage

```dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

## Usage

### 1. Define your schema

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

void buildTaskSchema(SchemaBuilder builder) {
  builder.table('tasks', (table) {
    table.guid('id');
    table.text('title');
    table.integer('completed');
    table.key(['id']).primary();
  });
}
```

### 2. Wrap your app with DatabaseProvider

```dart
void main() {
  runApp(
    DatabaseProvider(
      databaseName: 'tasks.db',
      schema: buildTaskSchema,
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
      home: const TaskScreen(),
    );
  }
}
```

### 3. Use QueryListView for reactive data

```dart
class TaskScreen extends StatelessWidget {
  const TaskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final database = DatabaseProvider.of(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: QueryListView<DbRecord>(
        query: (q) => q.from('tasks'),
        mapper: (row, db) => DbRecord(row, 'tasks', db),
        loadingBuilder: (context) => const CircularProgressIndicator(),
        errorBuilder: (context, error) => Text('Error: $error'),
        itemBuilder: (context, task) {
          return ListTile(
            title: Text(
              task.getValue('title')!,
              style: TextStyle(
                decoration: task.getValue('completed') == 1 
                    ? TextDecoration.lineThrough : null,
              ),
            ),
            onTap: () {
              // Toggle completion status
              final isCompleted = task.getValue('completed') == 1;
              database.update('tasks', 
                {'completed': isCompleted ? 0 : 1},
                where: 'id = ?', whereArgs: [task.getValue('id')],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add a new task
          database.insert('tasks', {
            'id': generateGuid(),
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
