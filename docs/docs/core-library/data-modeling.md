---
sidebar_position: 4
---

# Data Modeling with DbRecord

While working with raw `Map<String, Object?>` objects is flexible, it's not type-safe and can be error-prone. `declarative_sqlite` provides a `DbRecord` base class to help you create strongly-typed data models that map directly to your database tables and work seamlessly with the query system.

When combined with the `declarative_sqlite_generator` package, you can automate most of the boilerplate, giving you a clean, type-safe, and maintainable way to work with your data.

## The `DbRecord` Class

`DbRecord` is an abstract class that provides a foundation for your data models. It holds the raw data map but provides typed helper methods (`get`, `set`) and manages the "dirty" state of the record (i.e., whether it has unsaved changes).

### Creating a `DbRecord` Subclass

To create a model for a `tasks` table, you would define a `Task` class that extends `DbRecord`.

```dart title="lib/models/task.dart"
import 'package:declarative_sqlite/declarative_sqlite.dart';

class Task extends DbRecord {
  Task(super.data, super.database) : super(tableName: 'tasks');

  // Typed getters and setters (for manual implementation)
  String get title => get('title');
  // Only create setters manually for LWW columns
  set title(String value) => set('title', value); // Only if title is LWW
  
  // For non-LWW columns, provide only getters
  String get notes => get('notes');
  // No setter for non-LWW columns to prevent sync conflicts

  bool get isCompleted => get('is_completed') == 1;
  set isCompleted(bool value) => set('is_completed', value ? 1 : 0);

  DateTime? get dueDate => get('due_date');
  set dueDate(DateTime? value) => set('due_date', value);
}
```

### Saving Changes

The `DbRecord` class tracks which fields have been modified. You can persist these changes to the database by calling the `save()` method.

```dart
// Fetch a record and map it to a Task object
final tasks = await database.query((q) {
  q.from('tasks').where(col('id').eq('task-1'));
});
final task = Task(tasks.first.data, database);

// Modify the object
task.title = 'A new and improved title';
task.isCompleted = true;

// Save the changes to the database
// This will generate and run an UPDATE statement.
await task.save();
```
The `save()` method is intelligent: if the record doesn't exist in the database (i.e., it was created locally and has no primary key), `save()` will perform an `INSERT` instead of an `UPDATE`.

## LWW Columns and Update Safety

When designing data models for distributed systems, it's important to understand the distinction between LWW (Last-Write-Wins) and non-LWW columns:

- **LWW Columns**: Designed for conflict resolution in distributed systems. These columns can be safely updated on any row.
- **Non-LWW Columns**: Regular columns that should only be updated on locally-created rows to prevent synchronization conflicts.

When manually writing getters and setters, only create setters for LWW columns:

```dart
class Task extends DbRecord {
  // LWW column - safe to update
  String get title => get('title');
  set title(String value) => set('title', value);
  
  // Non-LWW column - read-only via generated getter
  String get notes => get('notes');
  // No setter - use setValue() for local-origin rows only
}
```

## Automating with Code Generation

Writing getters and setters for every column can be tedious. This is where `declarative_sqlite_generator` comes in.

### 1. Annotate Your Class

First, add the `@GenerateDbRecord` annotation to your class and include a `part` directive.

```dart title="lib/models/task.dart"
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'task.db.dart'; // Generated file

@GenerateDbRecord('tasks')
class Task extends DbRecord {
  Task(super.data, super.database) : super(tableName: 'tasks');

  // You can still define your own computed properties or methods
  bool get isOverdue => dueDate != null && dueDate!.isBefore(DateTime.now());
}
```

### 2. Run the Generator

Run the build runner command in your terminal:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Use the Generated Code

The generator will create a `task.db.dart` file containing a private extension `TaskGenerated` on your `Task` class. This extension has:
- A typed getter for every column in the `tasks` table.
- A typed setter for every LWW (Last-Write-Wins) column. Non-LWW columns only get getters to ensure data consistency in distributed systems.

You can now access the properties in a fully type-safe way. The generator automatically handles type conversions (e.g., for `DateTime`).

```dart
// The generated extension is private to the library, but the properties
// are accessible on your Task instance.
final task = Task(taskMap, database);

// Accessing generated properties
String title = task.title; // Type-safe getter (works for all columns)

// Setters are only generated for LWW columns
task.title = "New Title"; // ✅ Works if 'title' is marked as LWW

// For non-LWW columns, use setValue() for local-origin rows
if (task.isLocalOrigin) {
  task.setValue('notes', 'New notes'); // ✅ Explicit update for local rows
}

await task.save();
```

### Factory Registration

The generator also creates a `sqlite_factory_registration.dart` file. By calling `SqliteFactoryRegistration.registerAllFactories()` at startup, you register all your generated type factories.

This allows the database to automatically map query results to your typed `DbRecord` objects without you needing to provide a `mapper` function to `query()` or `streamRecords()`.

```dart
// No mapper function needed if factories are registered!
final Stream<List<Task>> taskStream = database.streamTyped<Task>((q) => q.from('tasks'));

taskStream.listen((List<Task> tasks) {
  // The stream now emits lists of strongly-typed Task objects directly.
});
```

## Next Steps

Learn how to manage file attachments for your records.

- **Next**: [File Management](./file-management.md)
