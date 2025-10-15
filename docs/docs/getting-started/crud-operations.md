---
sidebar_position: 4
---

# ✏️ CRUD Operations

`DeclarativeDatabase` provides straightforward methods for Create, Read, Update, and Delete (CRUD) operations. These methods wrap the underlying `sqflite` calls with additional features like exception mapping and automatic change notifications for streaming queries.

## ➕ Create (Insert)

There are two ways to insert records: using the database `insert` method directly, or using `DbRecord.save()` for a more object-oriented approach.

### Using Database Insert

The `insert` method takes the table name and a `Map<String, Object?>` representing the data to be inserted.

```dart
final database = DatabaseProvider.of(context);

await database.insert('tasks', {
  'id': const Uuid().v4(),
  'user_id': 'user-123',
  'title': 'Write documentation',
  'is_completed': 0,
});
```

### Using DbRecord.save() (Recommended)

When working with `DbRecord` objects, use the unified `save()` method which automatically handles both insert and update:

```dart
// Create a new task record
final task = Task({
  'user_id': 'user-123',
  'title': 'Write documentation',
  'is_completed': 0,
}, database);

// save() automatically detects this is a new record and performs an INSERT
await task.save();

// After save, the record has a system_id and is no longer new
print('Created task with ID: ${task.systemId}');
```

The `save()` method is intelligent and works for both new and existing records - see the Update section below for details.

## 🔍 Query (Read)

### Query for DbRecord objects

The `query` method returns `Future<List<DbRecord>>` for working with typed record objects:

```dart
final List<DbRecord> tasks = await database.query((q) => q.from('tasks'));
for (final task in tasks) {
  print('Task: ${task.getValue('title')}');
}
```

### Query for raw maps

The `queryMaps` method returns `Future<List<Map<String, Object?>>>` for simple data access:

```dart
final List<Map<String, Object?>> taskMaps = await database.queryMaps((q) => q.from('tasks'));
for (final task in taskMaps) {
  print('Task: ${task['title']}');
}
```

### Using WHERE clauses

For filtered queries, use `RawSqlWhereClause`:

```dart
// Find incomplete tasks for a specific user
final incompleteTasks = await database.query((q) => 
  q.from('tasks').where(RawSqlWhereClause(
    'user_id = ? AND is_completed = ?', 
    ['user-123', 0]
  ))
);

// Using the fluent query builder for more complex scenarios
final results = await database.query((q) {
  q.select('t.title, u.name as author')
    .from('tasks', 't')
    .innerJoin('users', col('t.user_id').eq(col('u.id')), 'u')
    .where(col('t.is_completed').eq(0))
    .orderBy(['t.due_date']);
});
```

## ✏️ Update

There are multiple ways to update records: using the database `update` method directly, or using `DbRecord.save()` for object-oriented updates.

### Using Database Update

The `update` method takes the table name, a `Map` of the new values, and an optional `where` clause to specify which records to update.

```dart
// Mark a specific task as completed
await database.update(
  'tasks',
  {'is_completed': 1},
  where: 'id = ?',
  whereArgs: ['task-guid-123'],
);
```

If you omit the `where` clause, **all records in the table will be updated**.

When updating a record in a table with system columns, the `system_version` and `system_modified_at` fields are automatically updated to reflect the change.

### Using DbRecord.save() (Recommended)

When working with `DbRecord` objects, the unified `save()` method provides the most convenient approach:

```dart
// Load an existing task
final tasks = await database.query((q) => 
  q.from('tasks').where(col('id').eq('task-guid-123'))
);
final task = Task(tasks.first.data, database);

// Modify the record
task.title = 'Updated title';
task.isCompleted = true;

// save() automatically detects this is an existing record and performs an UPDATE
await task.save();
```

The `save()` method tracks which fields have been modified and only updates those fields, making it efficient for partial updates.

#### Unified Save Approach

The beauty of `save()` is that you can use it for both insert and update without thinking about which operation to perform:

```dart
// Create or update a task - same code works for both!
final task = Task({'title': 'My task'}, database);

await task.save(); // INSERT (new record)

task.title = 'Updated task';
await task.save(); // UPDATE (existing record)

task.isCompleted = true;
await task.save(); // UPDATE again (existing record)
```

The `save()` method automatically determines the correct operation based on whether the record has a `system_id`.

## Delete

To remove records from a table, use the `delete` method. It takes the table name and an optional `where` clause.

```dart
// Delete a specific task
await database.delete(
  'tasks',
  where: 'id = ?',
  whereArgs: ['task-guid-123'],
);

// Delete all completed tasks
await database.delete(
  'tasks',
  where: 'is_completed = ?',
  whereArgs: [1],
);
```

If you omit the `where` clause, **all records in the table will be deleted**.

## Important: Transactions Not Supported

**Transactions are explicitly NOT supported** in DeclarativeDatabase and will throw `UnsupportedError`. This is intentional due to complexity with dirty row rollbacks, real-time streaming queries, and change notifications.

```dart
// DON'T DO THIS - Will throw UnsupportedError
try {
  await database.transaction((txn) async {
    await txn.delete('tasks', where: 'user_id = ?', whereArgs: ['user-123']);
    await txn.delete('users', where: 'id = ?', whereArgs: ['user-123']);
  });
} catch (e) {
  // UnsupportedError: Transactions are not supported in DeclarativeDatabase...
}
```

### Alternative Approaches

Instead of transactions, use separate operations with error handling:

```dart
// Use separate operations with proper error handling
try {
  await database.delete('tasks', where: 'user_id = ?', whereArgs: ['user-123']);
  await database.delete('users', where: 'id = ?', whereArgs: ['user-123']);
} catch (e) {
  // Handle errors and implement compensating actions if needed
  // For example: restore deleted tasks if user deletion fails
}
```

This design prioritizes simplicity, reliability, and real-time capabilities over traditional ACID transaction semantics.

## Next Steps

While `query` is great for one-time data reads, many applications need to react to data changes in real-time. Learn how to do this with streaming queries.

- **Next**: [Streaming Queries](../core-library/streaming-queries.md)
