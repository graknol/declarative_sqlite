---
sidebar_position: 6
---

# Data Synchronization

`declarative_sqlite` provides a powerful, built-in framework for implementing offline-first data synchronization. This allows your application to work seamlessly offline and sync its data with a remote server whenever a network connection is available.

The synchronization mechanism is built on three core concepts:
1.  **Hybrid Logical Clocks (HLCs)**: For conflict-free timestamping.
2.  **Automatic Change Tracking**: To record all local database modifications.
3.  **A Sync Manager**: To orchestrate communication with your server.

## 1. Hybrid Logical Clocks (HLCs)

At the heart of the sync system is the Hybrid Logical Clock. An HLC is a special type of timestamp that combines the physical time (wall clock) with a logical counter. This creates a unique, sortable timestamp that can be used to establish a clear, conflict-free order of events across distributed systems (like a client and a server).

When you use `declarative_sqlite`'s sync features, every row modification is stamped with an HLC value. This allows the server and client to determine which version of a row is newer, resolving conflicts using a "last-write-wins" strategy.

## 2. Enabling Change Tracking

To enable synchronization for a table, you must define it with `withSystemColumns: true` in your schema.

```dart
builder.table('tasks', (table) {
  // ... column definitions
},
// This is crucial for synchronization
withSystemColumns: true);
```

This adds several system columns to your table, including:
- `system_id`: A unique, client-generated ID for the row.
- `system_version`: The HLC timestamp of the last modification.
- `system_created_at`: The HLC timestamp of when the row was created.
- `is_deleted`: A soft-delete flag.

With this enabled, every `insert`, `update`, and `delete` operation is automatically recorded in a special `_dirty_rows` table. This table acts as an outbox of pending changes to be sent to the server.

## 3. Implementing the Sync Manager

The `ServerSyncManager` is the class that orchestrates the synchronization process. You need to provide it with two key functions: `onFetch` and `onSend`.

- **`onFetch`**: This function is responsible for fetching changes *from* the server. The manager will provide you with a map of the latest server timestamps it has for each table. Your function should call your backend API with these timestamps to get all records that are newer.
- **`onSend`**: This function is responsible for sending local changes *to* the server. The manager will provide a list of `DirtyRow` objects from the outbox. Your function should send these operations to your backend API.

### Example Implementation

In a Flutter app, you can use the `ServerSyncManagerWidget` to manage the lifecycle of the sync process.

```dart title="lib/widgets/sync_manager.dart"
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:flutter/material.dart';
import '../api/my_api_client.dart'; // Your API client

class SyncManager extends StatelessWidget {
  final Widget child;
  const SyncManager({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final database = DatabaseProvider.of(context);
    final apiClient = MyApiClient(); // Your API client instance

    return ServerSyncManagerWidget(
      database: database,
      // How often to attempt synchronization
      syncInterval: const Duration(minutes: 5),
      // Fetch changes from the server
      onFetch: (db, tableTimestamps) async {
        final remoteChanges = await apiClient.fetchChanges(tableTimestamps);
        // Apply changes to the local database
        await db.applyServerChanges(remoteChanges);
      },
      // Send local changes to the server
      onSend: (operations) async {
        try {
          await apiClient.sendChanges(operations);
          return true; // Return true on success
        } catch (e) {
          return false; // Return false on failure to retry later
        }
      },
      child: child,
    );
  }
}
```

You would then wrap your app with this `SyncManager` widget.

```dart title="lib/main.dart"
void main() {
  runApp(
    DatabaseProvider(
      // ...
      child: SyncManager(
        child: const MyApp(),
      ),
    ),
  );
}
```

## The Synchronization Flow

1.  **Local Change**: A user modifies a task in the app.
    - `declarative_sqlite` performs the `UPDATE` on the `tasks` table.
    - It automatically stamps the row with a new HLC timestamp.
    - It records the operation (e.g., `UPDATE tasks WHERE id = '...'`) in the `_dirty_rows` table.
2.  **Sync Interval**: The `ServerSyncManager` wakes up after its specified interval.
3.  **`onSend`**: The manager pulls the pending operations from `_dirty_rows` and passes them to your `onSend` function. Your API client sends them to the server.
4.  **Server Processing**: The server receives the operations. For each row, it compares the HLC timestamp from the client with the HLC timestamp it has for that row. It accepts the change only if the client's timestamp is newer (last-write-wins).
5.  **`onFetch`**: The manager calls your `onFetch` function, providing the last known server timestamps. Your API client fetches any changes from the server that have occurred since the last sync.
6.  **Apply Server Changes**: The fetched changes are applied to the local database using `database.applyServerChanges()`. This method intelligently inserts or updates records based on the incoming data, again respecting HLC timestamps to prevent overwriting newer local changes with older server data.

This robust, two-way process ensures that data remains consistent across the client and server, even with intermittent network connectivity.
