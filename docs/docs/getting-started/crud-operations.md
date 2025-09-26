---
sidebar_position: 4
---

# CRUD Operations

`DeclarativeDatabase` provides straightforward methods for Create, Read, Update, and Delete (CRUD) operations. These methods wrap the underlying `sqflite` calls with additional features like exception mapping and automatic change notifications for streaming queries.

## Insert

To add a new record to a table, use the `insert` method. It takes the table name and a `DbRecord` or `Map<String, Object?>` representing the data to be inserted.

```dart
final database = DatabaseProvider.of(context);

await database.insert('tasks', {
  'id': const Uuid().v4(),
  'user_id': 'user-123',
  'title': 'Write documentation',
  'is_completed': 0,
});
```

## Query (Read)

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

## Update

To modify existing records, use the `update` method. It takes the table name, a `Map` of the new values, and an optional `where` clause to specify which records to update.

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
