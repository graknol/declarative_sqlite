---
sidebar_position: 4
---

# CRUD Operations

`DeclarativeDatabase` provides straightforward methods for Create, Read, Update, and Delete (CRUD) operations. These methods wrap the underlying `sqflite` calls with additional features like exception mapping and automatic change notifications for streaming queries.

## Insert

To add a new record to a table, use the `insert` method. It takes the table name and a `Map<String, Object?>` representing the data to be inserted.

```dart
final database = DatabaseProvider.of(context);

await database.insert('tasks', {
  'id': Uuid().v4(),
  'user_id': 'user-123',
  'title': 'Write documentation',
  'is_completed': 0,
});
```

If the table has system columns enabled (`withSystemColumns: true`), the `insert` method will automatically generate and populate the `system_id`, `system_created_at`, and `system_version` fields.

## Query (Read)

To read data from the database, use the `query` method. It returns a `Future<List<Map<String, Object?>>>`.

### Simple Query

Fetch all records from a table.

```dart
final List<Map<String, Object?>> tasks = await database.query('tasks');
print(tasks);
// Output: [{'id': '...', 'title': 'Write documentation', ...}]
```

### Using the Query Builder

For more complex queries involving `WHERE` clauses, `JOIN`s, `ORDER BY`, etc., you can use the powerful query builder.

```dart
// Find all incomplete tasks for a specific user, ordered by due date.
final incompleteTasks = await database.query(
  'tasks',
  where: 'user_id = ? AND is_completed = ?',
  whereArgs: ['user-123', 0],
  orderBy: 'due_date ASC',
);

// Using the fluent query builder for more complex scenarios
final results = await database.queryWithBuilder((q) {
  q
      .select('t.title, u.name as author')
      .from('tasks', as: 't')
      .join('users', on: 't.user_id = u.id', as: 'u')
      .where(col('t.is_completed').eq(0))
      .orderBy('t.due_date');
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

## Transactions

For operations that need to be atomic (either all succeed or all fail), you can use the `transaction` method. If any error occurs within the transaction block, all changes made inside it are automatically rolled back.

```dart
await database.transaction((txn) async {
  // 'txn' is a transaction-aware database instance
  await txn.delete('tasks', where: 'user_id = ?', whereArgs: ['user-123']);
  await txn.delete('users', where: 'id = ?', whereArgs: ['user-123']);
});
```

## Next Steps

While `query` is great for one-time data reads, many applications need to react to data changes in real-time. Learn how to do this with streaming queries.

- **Next**: [Streaming Queries](../core-library/streaming-queries.md)
