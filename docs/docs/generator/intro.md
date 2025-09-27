---
sidebar_position: 1
---

# Code Generation

The `declarative_sqlite_generator` package is a powerful tool that uses `build_runner` to automate the creation of boilerplate code. By using code generation, you can significantly improve type safety, reduce manual coding, and make your data models more robust and easier to maintain.

## Why Use Code Generation?

When working with `DbRecord`, you could write typed getters and setters manually for each column. However, this has several drawbacks:
-   It's tedious and repetitive.
-   It's error-prone. A typo in a column name string (`get('titel')`) won't be caught by the compiler.
-   It requires manual updates. If you rename a column in your schema, you have to remember to update the getter/setter in your model class.

Code generation solves these problems by reading your schema directly and creating the necessary code for you.

## What It Generates

For each class annotated with `@GenerateDbRecord`, the generator produces a `.db.dart` part file containing a private extension. This extension includes:
1.  **Typed Getters**: A getter for each column in the associated table, with the correct Dart type.
2.  **Typed Setters**: A setter for each LWW (Last-Write-Wins) column, with type validation. Non-LWW columns only get getters to enforce data consistency in distributed systems.

Additionally, it generates a single `sqlite_factory_registration.dart` file for your entire project, which allows the database to automatically map query results to your typed objects.

## Setup and Configuration

### 1. Add Dependencies

Ensure you have `declarative_sqlite_generator` and `build_runner` in your `dev_dependencies`.

```yaml title="pubspec.yaml"
dependencies:
  declarative_sqlite: ^1.0.2

dev_dependencies:
  build_runner: ^2.4.10
  declarative_sqlite_generator: ^1.0.2
```

### 2. Define Your Schema with @DbSchema

Create a separate schema file and mark your schema function with the `@DbSchema()` annotation:

```dart title="lib/database/schema.dart"
import 'package:declarative_sqlite/declarative_sqlite.dart';

@DbSchema()
void buildAppSchema(SchemaBuilder builder) {
  builder.table('tasks', (table) {
    table.guid('id');
    table.text('title').lww(); // LWW column - will get both getter and setter
    table.text('notes');       // Non-LWW column - will only get getter
    table.integer('completed');
    table.key(['id']).primary();
  });
  
  builder.table('users', (table) {
    table.guid('id');
    table.text('name').lww(); // LWW column - will get both getter and setter
    table.text('email');      // Non-LWW column - will only get getter
    table.key(['id']).primary();
  });
}
```

### 3. Annotate Your Models

In your model file, add the `@GenerateDbRecord('table_name')` annotation above your class definition and include the `part` directive.

```dart title="lib/models/task.dart"
import 'package:declarative_sqlite/declarative_sqlite.dart';

// This line links the generated file to this one.
part 'task.db.dart';

@GenerateDbRecord('tasks')
class Task extends DbRecord {
  Task(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'tasks', database);
}
```

## Running the Generator

To run the code generator, use the `build_runner` command in your terminal:

```bash
# Run a one-time build
dart run build_runner build --delete-conflicting-outputs

# Or, run in watch mode to automatically rebuild on changes
dart run build_runner watch --delete-conflicting-outputs
```

This will create the `task.db.dart` and `sqlite_factory_registration.dart` files.

## Using the Generated Code

### Initialize Factory Registration

In your application's entry point (`main.dart`), import and call the generated `SqliteFactoryRegistration.registerAllFactories()` function. This must be done before you initialize your database.

```dart title="lib/main.dart"
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'models/task.dart';
import 'sqlite_factory_registration.dart';
import 'database/schema.dart';

void main() {
  // Register all generated DbRecord factories
  SqliteFactoryRegistration.registerAllFactories();

  runApp(
    DatabaseProvider(
      databaseName: 'app.db',
      schema: buildAppSchema,
      child: const MyApp(),
    ),
  );
}
```

### Using Typed Properties

Now you can interact with your `Task` object in a type-safe manner using the generated extensions and base class methods.

```dart
// Create a task instance
final task = Task({}, 'tasks', database);

// Use the typed getters for all columns
print('Current title: ${task.title}');
print('Current notes: ${task.notes}');

// Use typed setters for LWW columns only
task.title = 'Complete the documentation'; // ✅ Works (LWW column)

// For non-LWW columns, use setValue() method for local-origin rows
if (task.isLocalOrigin) {
  task.setValue('notes', 'Additional notes'); // ✅ Works for local rows
} else {
  // task.notes = 'value'; // ❌ Compile error - no setter generated
  // task.setValue('notes', 'value'); // ❌ Runtime error on server rows
}

// Insert the task
await database.insert('tasks', task.data);

// Query tasks with type-safe mapping
final taskStream = database.streamQuery<Task>(
  (q) => q.from('tasks'),
  mapper: (row, db) => Task(row, 'tasks', db),
);

taskStream.stream.listen((tasks) {
  for (final task in tasks) {
    print('Task: ${task.title}, Notes: ${task.notes}');
  }
});
```

### Generated Code Structure

The generator creates different code for LWW and non-LWW columns:

```dart
// Generated extension in task.db.dart
extension TaskGenerated on Task {
  // LWW column - gets both getter and setter
  String get title => getTextNotNull('title');
  set title(String value) => setText('title', value);
  
  // Non-LWW column - only getter, with explanation
  String get notes => getTextNotNull('notes');
  /// Note: notes is not an LWW column, so no setter is generated.
  /// Use setValue('notes', value) for local-origin rows.
  
  // Primary key - only getter (immutable)
  String get id => getTextNotNull('id');
}
```

This design ensures data consistency by preventing accidental updates to non-LWW columns on server-origin rows, while still allowing typed read access to all columns.

This design ensures data consistency by preventing accidental updates to non-LWW columns on server-origin rows, while still allowing typed read access to all columns.

## Understanding LWW Columns and Generated Setters

The generator only creates setters for columns marked as LWW (Last-Write-Wins) to maintain data consistency in distributed systems:

### LWW vs Non-LWW Columns

- **LWW Columns**: Designed for conflict resolution in distributed systems. Updates to these columns are safe on both local and server-origin rows.
- **Non-LWW Columns**: Regular columns that should only be updated on locally-created rows to prevent synchronization conflicts.

### Why This Matters

In distributed applications, most data rows originate from the server. Generating setters for all columns would make it easy to accidentally update non-LWW columns on server-origin rows, causing data consistency issues.

```dart
// With LWW column - safe to update anytime
task.title = "New Title"; // ✅ Always works

// With non-LWW column - requires explicit handling
if (task.isLocalOrigin) {
  task.setValue('notes', 'New Notes'); // ✅ Safe for local rows
} else {
  // Cannot update - would cause sync conflicts
  // task.setValue('notes', 'New Notes'); // ❌ Throws StateError
}
```

### Marking Columns as LWW

To generate setters for a column, mark it as LWW in your schema:

```dart
builder.table('tasks', (table) {
  table.text('title').lww(); // Gets setter
  table.text('notes');       // No setter generated
});
```

By leveraging code generation, you create a more robust, maintainable, and developer-friendly data layer for your application.
