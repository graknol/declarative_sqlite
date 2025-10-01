---
sidebar_position: 3
---

# 🌊 Streaming Queries

Streaming queries are the cornerstone of building reactive applications with `declarative_sqlite`. Instead of fetching data just once, a streaming query returns a `Stream` that automatically emits a new, updated list of results whenever the underlying data changes.

This is ideal for UI development, as you can simply listen to the stream and rebuild your widgets whenever new data arrives, without needing to manually track state or re-fetch data.

## Creating a Streaming Query

You create a streaming query using the `database.streamRecords()` method. It uses the same query builder syntax as the regular `query()` method.

```dart
// Create a stream of all tasks
final Stream<List<DbRecord>> taskStream = database.streamRecords((q) => q.from('tasks'));

// Listen to the stream
final subscription = taskStream.listen((tasks) {
  print('Tasks updated! New count: ${tasks.length}');
  // In a Flutter app, you would use StreamBuilder widget
});

// Later, when you modify the data...
await database.insert('tasks', {'id': 't4', 'title': 'A new task'});
// ...the stream will automatically emit the new list of tasks.
```

You can also use filtered streaming queries:

```dart
final activeTaskStream = database.streamRecords((q) => 
  q.from('tasks').where(RawSqlWhereClause('is_completed = ?', [0]))
);
```

## How It Works: Dependency Analysis

`declarative_sqlite` contains a sophisticated **query dependency analyzer**. When you create a streaming query, the analyzer inspects your query to determine exactly which tables and columns it depends on.

For example, the query `SELECT title FROM tasks WHERE is_completed = 0` depends on:
- The `tasks` table.
- The `title` and `is_completed` columns.

The `QueryStreamManager` then listens for any changes (inserts, updates, or deletes) that affect the `tasks` table. If a relevant change occurs, it intelligently decides whether to re-run the query.

- An `UPDATE` to the `is_completed` column of any task will trigger a refresh.
- An `UPDATE` to the `description` column will **not** trigger a refresh, because the query doesn't depend on it.
- An `INSERT` into the `tasks` table will always trigger a refresh.

This precise, column-level dependency tracking ensures that queries are only re-executed when absolutely necessary, making the system highly efficient. For very complex queries (e.g., with complex joins or subqueries), the analyzer may fall back to table-level dependency tracking to ensure correctness.

## Caching and Performance

To further improve performance, streaming queries use an internal cache. For queries on tables with system columns (`withSystemColumns: true`), the manager can perform optimizations:

1.  **Initial Fetch**: The query is run, and the results are mapped to objects and stored in a cache, indexed by their `system_id`.
2.  **On Data Change**: Instead of re-running the entire query, the manager can often fetch only the rows that have changed (based on their `system_version`).
3.  **Cache Update**: It then updates the cached objects with the new data and emits a new list constructed from the cache.

This "delta-updating" approach is much faster than re-fetching and re-mapping hundreds of rows, especially for large result sets where only a few items have changed.

## Using `streamRecords` with Typed Objects

While `streamRecords` returns a `Stream<List<DbRecord>>`, you'll typically want to work with your own typed objects (e.g., `Task`, `User`). You can use `streamTyped<T>()` to automatically get typed objects, or use the `.map()` method on the stream to convert the records into your objects.

If you are using the code generator, this mapping can be done automatically.

```dart
// Using typed streaming for automatic conversion
final Stream<List<Task>> taskObjectStream = database
    .streamTyped<Task>((q) => q.from('tasks'));

// Or manually converting records to typed objects
final Stream<List<Task>> taskObjectStream = database
    .streamRecords((q) => q.from('tasks'))
    .map((listOfRecords) => listOfRecords.map((record) => Task.fromDbRecord(record)).toList());

taskObjectStream.listen((List<Task> tasks) {
  // Now you have a list of strongly-typed Task objects
});
```

In Flutter, the `QueryListView` widget handles this mapping for you automatically.

## Next Steps

Learn how to model your data using `DbRecord` classes and how the code generator can automate the creation of typed accessors and mapping logic.

- **Next**: [Data Modeling with DbRecord](./data-modeling.md)
