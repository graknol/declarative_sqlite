---
sidebar_position: 6
---

# 🔄 Data Synchronization

`declarative_sqlite` provides a powerful, built-in framework for implementing offline-first data synchronization. This allows your application to work seamlessly offline and sync its data with a remote server whenever a network connection is available.

The synchronization mechanism is built on three core concepts:
1.  **Hybrid Logical Clocks (HLCs)**: For conflict-free timestamping.
2.  **Automatic Change Tracking**: To record all local database modifications.
3.  **A Sync Manager**: To orchestrate communication with your server.

## 1. Hybrid Logical Clocks (HLCs)

At the heart of the sync system is the Hybrid Logical Clock. An HLC is a special type of timestamp that combines the physical time (wall clock) with a logical counter. This creates a unique, sortable timestamp that can be used to establish a clear, conflict-free order of events across distributed systems (like a client and a server).

When you use `declarative_sqlite`'s sync features, every row modification is stamped with an HLC value. This allows the server and client to determine which version of a row is newer, resolving conflicts using a "last-write-wins" strategy.

## 2. Automatic Change Tracking

All user tables in `declarative_sqlite` automatically include system columns for synchronization. These columns are added automatically when you define a table:

```dart
builder.table('tasks', (table) {
  table.guid('id').notNull().primary();
  table.text('title').notNull();
  // ... other column definitions
});
```

The library automatically adds several system columns to your table, including:
- `system_id`: A unique, client-generated ID for the row.
- `system_version`: The HLC timestamp of the last modification.
- `system_created_at`: The HLC timestamp of when the row was created.
- `system_is_local_origin`: Tracks whether the row was created locally (1) or came from the server (0).

With these system columns, every `insert`, `update`, and `delete` operation is automatically recorded in a special `__dirty_rows` table. This table acts as an outbox of pending changes to be sent to the server.

## Column Update Restrictions

To maintain data consistency in distributed systems, the library enforces specific rules about which columns can be updated:

- **Newly created rows**: All columns can be set during initial creation
- **Locally created rows**: All columns can be updated after creation
- **Server-originating rows**: Only columns marked as LWW (Last-Write-Wins) can be updated

This prevents conflicts and ensures that only appropriate data synchronizes between clients and servers.

```dart
// Example: Define a table with both LWW and non-LWW columns
builder.table('tasks', (table) {
  table.guid('id').notNull().primary();
  table.text('title').notNull().lww(); // Can be updated on server rows
  table.text('notes').notNull();       // Cannot be updated on server rows
  table.integer('priority').notNull(); // Cannot be updated on server rows
});
```

## 3. Implementing Synchronization Logic

With change tracking enabled, you can now implement your own synchronization logic. The core of this is the `__dirty_rows` table, which acts as an outbox of pending changes.

You can get the list of dirty rows by calling `database.getDirtyRows()`.

```dart
final dirtyRows = await database.getDirtyRows();
```

Each `DirtyRow` object contains:
- `tableName`: The name of the table that was changed.
- `rowId`: The `system_id` of the row that was changed.
- `hlc`: The Hybrid Logical Clock timestamp of the change.
- `isFullRow`: Whether the full row should be synchronized (true for local origin) or only LWW columns (false for server origin).

You can then use this information to fetch the full record from the database and send it to your server. The `isFullRow` field helps determine what data to include in the sync payload.

## Handling Update Restrictions

When working with records that originated from the server, attempting to update non-LWW columns will throw a `StateError`:

```dart
// This will work - 'title' is marked as LWW
record.setValue('title', 'New Title');

// This will throw StateError - 'notes' is not LWW and row came from server
record.setValue('notes', 'New Notes'); // StateError!
```

To check if a record allows unrestricted updates:

```dart
if (record.isLocalOrigin) {
  // Can update any column
  record.setValue('notes', 'New Notes');
} else {
  // Can only update LWW columns
  record.setValue('title', 'New Title'); // Only if 'title' is LWW
}
```

### Generated Code Safety

When using the code generator, setters are only generated for LWW columns. This provides compile-time safety against accidental non-LWW updates:

```dart
// Generated extension provides setters only for LWW columns
task.title = "New Title";    // ✅ Works (LWW column has setter)
// task.notes = "New Notes"; // ❌ Compile error (no setter generated)

// For non-LWW columns, use setValue() explicitly
if (task.isLocalOrigin) {
  task.setValue('notes', 'New Notes'); // ✅ Explicit intent for local rows
}
```

This design prevents most synchronization errors at compile time while still allowing explicit updates to non-LWW columns when appropriate.

### Example Synchronization Service

Here is an example of a simple synchronization service that sends pending changes to a server.

```dart
class MySyncService {
  final DeclarativeDatabase database;
  final MyApiClient apiClient; // Your API client

  MySyncService(this.database, this.apiClient);

  Future<void> performSync() async {
    await _sendLocalChanges();
    await _fetchRemoteChanges();
  }

  Future<void> _sendLocalChanges() async {
    final dirtyRows = await database.getDirtyRows();
    if (dirtyRows.isEmpty) return;

    final recordsToSend = <Map<String, dynamic>>[];
    for (final dirtyRow in dirtyRows) {
      final record = await database.query(
        (q) => q.from(dirtyRow.tableName)
              .where(col('system_id').equals(dirtyRow.rowId))
      );
      if (record.isNotEmpty) {
        recordsToSend.add(record.first.toJson());
      }
    }

    try {
      await apiClient.sendChanges(recordsToSend);
      // If successful, clear the dirty rows that were sent
      await database.dirtyRowStore?.remove(dirtyRows);
    } catch (e) {
      // Handle error, maybe log it or retry later
    }
  }

  Future<void> _fetchRemoteChanges() async {
    // You need to manage the last sync timestamp yourself
    final lastSyncTimestamp = await _getLastSyncTimestamp();
    final remoteChanges = await apiClient.fetchChanges(lastSyncTimestamp);

    // The `bulkLoad` method is useful for applying server changes
    // as it handles inserts and updates based on `system_id`
    // and respects HLC timestamps for LWW columns.
    for (final tableName in remoteChanges.keys) {
      await database.bulkLoad(tableName, remoteChanges[tableName]!);
    }

    await _setLastSyncTimestamp(DateTime.now());
  }

  Future<void> _fetchRemoteChangesWithErrorHandling() async {
    final lastSyncTimestamp = await _getLastSyncTimestamp();
    final remoteChanges = await apiClient.fetchChanges(lastSyncTimestamp);

    // Handle constraint violations gracefully during sync
    for (final tableName in remoteChanges.keys) {
      await database.bulkLoad(
        tableName, 
        remoteChanges[tableName]!,
        onConstraintViolation: ConstraintViolationStrategy.skip,
      );
    }

    await _setLastSyncTimestamp(DateTime.now());
  }

  Future<DateTime?> _getLastSyncTimestamp() async {
    // Implementation to get the last sync timestamp from storage
    return null;
  }

  Future<void> _setLastSyncTimestamp(DateTime timestamp) async {
    // Implementation to save the last sync timestamp to storage
  }
}
```

## The Synchronization Flow

1.  **Local Change**: A user modifies a task in the app.
    - `declarative_sqlite` performs the `UPDATE` on the `tasks` table.
    - It automatically stamps the row with a new HLC timestamp.
    - It records the operation (e.g., `UPDATE tasks WHERE id = '...'`) in the `__dirty_rows` table.
2.  **Trigger Sync**: You trigger the synchronization process, for example, by calling `MySyncService.performSync()` periodically or in response to network status changes.
3.  **Send Local Changes**: The service pulls the pending operations from `__dirty_rows`, fetches the full records, and sends them to your server.
4.  **Server Processing**: The server receives the records. For each row, it compares the HLC timestamp from the client with the HLC timestamp it has for that row. It accepts the change only if the client's timestamp is newer (last-write-wins).
5.  **Fetch Remote Changes**: The service calls your `onFetch` function, providing the last known server timestamps. Your API client fetches any changes from the server that have occurred since the last sync.
6.  **Apply Server Changes**: The fetched changes are applied to the local database using `database.bulkLoad()`. This method intelligently inserts or updates records based on the incoming data, again respecting HLC timestamps to prevent overwriting newer local changes with older server data.

This robust, two-way process ensures that data remains consistent across the client and server, even with intermittent network connectivity.

## Handling Constraint Violations During Sync

When synchronizing data from a server, you may encounter constraint violations (unique constraints, primary key conflicts, etc.). The `bulkLoad` method provides graceful handling of these scenarios through the `onConstraintViolation` parameter.

### Constraint Violation Strategies

```dart
enum ConstraintViolationStrategy {
  throwException, // Default: Throws the original exception
  skip,          // Silently skips problematic rows and continues
}
```

### Usage Examples

**Default Behavior (Throw on Violations):**
```dart
// This will throw an exception if any row violates constraints
await database.bulkLoad(tableName, serverData);
```

**Skip Problematic Rows:**
```dart
// This will skip rows that violate constraints and continue processing valid ones
await database.bulkLoad(
  tableName, 
  serverData,
  onConstraintViolation: ConstraintViolationStrategy.skip,
);
```

### Common Synchronization Scenarios

**Scenario 1: Preserve Local Data**
When you want to keep existing local data and only add new records from the server:

```dart
await database.bulkLoad(
  'users', 
  serverUsers,
  onConstraintViolation: ConstraintViolationStrategy.skip,
);
// Local users with conflicting emails/IDs remain unchanged
// New users from server are added successfully
```

**Scenario 2: Audit and Handle Conflicts**
When you need to know about conflicts for business logic or user notification:

```dart
try {
  await database.bulkLoad('products', serverProducts);
} catch (e) {
  if (e.toString().contains('constraint violation')) {
    // Handle conflict - maybe prompt user or log for review
    await _handleDataConflict(e);
  }
}
```

### Monitoring Constraint Violations

When using `ConstraintViolationStrategy.skip`, violations are automatically logged for monitoring:

```dart
// Logs appear as:
// ⚠️ Skipping row due to constraint violation in INSERT on table users: 
// UNIQUE constraint failed: users.email
```

This logging helps you:
- Monitor data quality issues
- Identify frequent constraint violations
- Debug synchronization problems
- Audit skipped records for business review
