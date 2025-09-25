---
sidebar_position: 4
---

# ServerSyncManagerWidget

`ServerSyncManagerWidget` is a lifecycle-aware Flutter widget that manages the background data synchronization process. It wraps the `ServerSyncManager` from the core library, automatically starting the sync service when the widget is created and stopping it when it's disposed.

This widget is the easiest way to implement two-way data synchronization in a Flutter application.

## Usage

To use it, wrap a high-level widget in your tree (often right inside your `DatabaseProvider`) with `ServerSyncManagerWidget`. You must provide it with `onFetch` and `onSend` callbacks.

```dart title="lib/main.dart"
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'api/my_api_client.dart'; // Your custom API client
import 'database/schema.dart';

void main() {
  runApp(
    DatabaseProvider(
      databaseName: 'app.db',
      schema: appSchema,
      child: Builder(
        builder: (context) {
          final database = DatabaseProvider.of(context);
          final apiClient = MyApiClient(); // Your API client

          return ServerSyncManagerWidget(
            database: database,
            // How often to attempt a sync cycle
            syncInterval: const Duration(minutes: 15),
            // Define how to fetch changes from your server
            onFetch: (db, tableTimestamps) async {
              final remoteChanges = await apiClient.fetchChanges(tableTimestamps);
              await db.applyServerChanges(remoteChanges);
            },
            // Define how to send local changes to your server
            onSend: (operations) async {
              try {
                await apiClient.sendChanges(operations);
                return true; // Success
              } catch (e) {
                // Returning false tells the manager the send failed,
                // and the operations will be retried on the next cycle.
                return false;
              }
            },
            child: const MyApp(),
          );
        },
      ),
    ),
  );
}
```

### Parameters

-   `database` (required): The `DeclarativeDatabase` instance, usually obtained from `DatabaseProvider.of(context)`.
-   `child` (required): The application's widget tree.
-   `onFetch` (required): An async callback function responsible for fetching remote changes from your server. It receives the database instance and a map of the last known server timestamps for each table.
-   `onSend` (required): An async callback function responsible for sending local changes to your server. It receives a list of `DirtyRow` objects. It should return `true` on success and `false` on failure.
-   `syncInterval` (optional): The `Duration` between synchronization attempts. Defaults to 15 minutes.
-   `initialSyncDelay` (optional): A `Duration` to wait before the first sync cycle runs. This can be useful to allow the app to fully start up before initiating network activity.

## The Synchronization Callbacks

### `onFetch`
Your `onFetch` implementation needs to communicate with your backend to get all records that have been updated since the last successful sync.

```dart
// Example onFetch implementation
onFetch: (db, tableTimestamps) async {
  print('Fetching changes from server...');
  // tableTimestamps might look like: {'tasks': 'hlc-timestamp-123', 'users': 'hlc-timestamp-456'}
  final remoteChanges = await apiClient.fetchChanges(tableTimestamps);

  // remoteChanges should be a list of maps, where each map is a row from the server.
  // applyServerChanges will intelligently insert or update the local records.
  await db.applyServerChanges(remoteChanges);
  print('Fetch complete!');
}
```

### `onSend`
Your `onSend` implementation receives a list of `DirtyRow` objects. Each object represents a single CUD (Create, Update, Delete) operation that occurred locally. You need to serialize this list and send it to your backend.

```dart
// Example onSend implementation
onSend: (operations) async {
  if (operations.isEmpty) {
    print('No local changes to send.');
    return true;
  }

  print('Sending ${operations.length} local changes to server...');
  try {
    // Your API client should handle converting the DirtyRow objects
    // into a format your backend understands (e.g., JSON).
    await apiClient.sendChanges(operations);
    print('Send successful!');
    return true; // On success, the sent operations are removed from the local outbox.
  } catch (e) {
    print('Failed to send changes: $e');
    return false; // On failure, the operations remain in the outbox to be retried later.
  }
}
```

By using `ServerSyncManagerWidget`, you get a robust, lifecycle-aware, and battery-conscious background synchronization system with minimal setup.
