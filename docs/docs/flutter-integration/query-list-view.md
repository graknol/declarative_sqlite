---
sidebar_position: 3
---

# 📋 QueryListView

`QueryListView` is a specialized Flutter widget that simplifies the process of displaying a list of data from a `declarative_sqlite` streaming query. It's a reactive `ListView` that automatically updates its contents when the underlying data in the database changes.

It handles several key tasks for you:
-   Subscribing to a `streamQuery`.
-   Building the UI for the initial list of items.
-   Efficiently adding, removing, or updating items in the list using `AnimatedList` when the stream emits new data.
-   Managing the stream subscription lifecycle.

## Usage

To use `QueryListView`, you need to provide it with a `database` instance and a `query` function.

```dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

class TaskList extends StatelessWidget {
  const TaskList({super.key});

  @override
  Widget build(BuildContext context) {
    return QueryListView<DbRecord>(
      query: (q) => q.from('tasks'),
      mapper: (row, db) => DbRecord(row, 'tasks', db),
      itemBuilder: (context, task) {
        return ListTile(
          title: Text(task.getValue('title') as String),
          subtitle: Text('Due: ${task.getValue('due_date')}'),
          trailing: Checkbox(
            value: (task.getValue('is_completed') as int) == 1,
            onChanged: (isCompleted) async {
              final database = DatabaseProvider.of(context);
              await database.update(
                'tasks',
                {'is_completed': isCompleted == true ? 1 : 0},
                where: 'id = ?',
                whereArgs: [task.getValue('id')],
              );
            },
          ),
        );
      },
      loadingBuilder: (context) => const Center(child: CircularProgressIndicator()),
      // Optional: A widget to show when the query returns no results
      emptyBuilder: (context) => const Center(child: Text('No tasks yet!')),
    );
  }
}
```

### Parameters

-   `database` (required): The `DeclarativeDatabase` instance.
-   `query` (required): A function that takes a `QueryBuilder` and defines the query to be streamed.
-   `itemBuilder` (required): A function that builds the widget for each record in the result set. It receives the `BuildContext` and the data item (as a `DbRecord` or a typed subclass).
-   `loadingBuilder` (optional): A widget to display while waiting for the first set of results from the stream.
-   `emptyBuilder` (optional): A widget to display if the stream emits an empty list.
-   `mapper` (optional): If you are not using generated and registered factories, you can provide a custom function to map the `DbRecord` to your typed object.
-   `sort` (optional): A client-side sort function to apply to the results after they are fetched from the database.
-   `reverse`: Whether to reverse the order of the list.

## How It Works

1.  **Initialization**: When `QueryListView` is built, it calls `database.streamRecords()` with the provided `query`.
2.  **Subscription**: It subscribes to the returned stream.
3.  **Initial Build**: While waiting for the first event, it shows the `loadingBuilder`. When the first list of data arrives, it builds the list of items using `itemBuilder`.
4.  **Reactive Updates**: The underlying `QueryStreamManager` monitors the database for changes relevant to the query.
    -   When a relevant `INSERT`, `UPDATE`, or `DELETE` occurs, the stream emits a new list of results.
    -   `QueryListView` receives the new list and intelligently calculates the difference between the old list and the new one.
    -   It uses an `AnimatedList` to perform efficient UI updates: inserting, removing, or updating only the items that have changed, resulting in smooth animations.

By using `QueryListView`, you can create a reactive UI that is always in sync with your database with very little code, letting you focus on the appearance and behavior of your list items.
