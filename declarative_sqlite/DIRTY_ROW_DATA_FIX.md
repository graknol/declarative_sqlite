# Dirty Row Data Field Fix

## Problem Statement

Previously, when using `db.update()` to update rows, the dirty row store was marking rows as dirty but the `data` field in `DirtyRow` was undefined. This caused sync operations to fail with:

```
Cannot convert undefined or null to object
```

This error occurred when trying to call `Object.entries(dirtyRow.data)` in sync operations.

## Solution

We've added a `data` field to the `DirtyRow` class that captures the actual values that were changed during database operations. This allows sync operations to know exactly which fields were modified and push only those specific changes to the remote API.

## Changes Made

### 1. DirtyRow Class (`dirty_row.dart`)
- Added optional `data` field: `Map<String, Object?>? data`
- The field stores the values that were changed in the operation
- Made optional for backward compatibility

### 2. DirtyRowStore Interface (`dirty_row_store.dart`)
- Updated `add()` method signature to accept an optional data parameter
- Signature: `Future<void> add(String tableName, String rowId, Hlc hlc, bool isFullRow, [Map<String, Object?>? data])`

### 3. SqliteDirtyRowStore Implementation (`sqlite_dirty_row_store.dart`)
- Added JSON serialization/deserialization for storing data in SQLite
- Uses Dart's built-in `dart:convert` library for reliable JSON encoding
- Stores data as JSON text in the database
- Retrieves and deserializes data when reading dirty rows

### 4. Schema Builder (`schema_builder.dart`)
- Added `data` column to `__dirty_rows` system table
- Column type: TEXT (nullable)
- Stores JSON-encoded changed values

### 5. DeclarativeDatabase (`declarative_database.dart`)
- **Insert operations**: Pass all inserted values to dirty row store
- **Update operations**: Pass only the changed values to dirty row store
- **Delete operations**: Pass null for data (row is being removed)

### 6. Test Coverage (`dirty_row_data_test.dart`)
- Comprehensive test suite verifying data field functionality
- Tests for insert, update, and delete operations
- Tests for data persistence and various data types
- Tests for special characters and edge cases

## Usage Example

### Before (Broken)
```dart
await db.update('c_work_order', {
  'rowstate': 'WorkStarted',
}, {
  where: 'system_id = ?',
  whereArgs: ['some-id']
});

// In sync operation:
final dirtyRows = await database.getDirtyRows();
for (final dirtyRow in dirtyRows) {
  // ❌ dirtyRow.data was undefined!
  // This would crash: Object.entries(dirtyRow.data)
}
```

### After (Fixed)
```dart
await db.update('c_work_order', {
  'rowstate': 'WorkStarted',
}, {
  where: 'system_id = ?',
  whereArgs: ['some-id']
});

// In sync operation:
final dirtyRows = await database.getDirtyRows();
for (final dirtyRow in dirtyRows) {
  // ✅ dirtyRow.data now contains the changed values!
  if (dirtyRow.data != null) {
    print(dirtyRow.data); // { rowstate: 'WorkStarted' }
    
    // Push specific changes to API
    await apiClient.updateRow(
      table: dirtyRow.tableName,
      id: dirtyRow.rowId,
      changes: dirtyRow.data!,
    );
  }
}
```

## Benefits

1. **Sync Operations Work**: Sync code can now access the changed values without errors
2. **Bandwidth Efficiency**: Only changed fields need to be sent to the API
3. **Better Debugging**: Developers can see exactly what changed in each dirty row
4. **API Efficiency**: Reduces unnecessary data transfer and processing
5. **Conflict Resolution**: Enables more granular conflict detection and resolution

## Migration Notes

### Backward Compatibility
- The `data` field is optional (nullable), so existing code continues to work
- Existing dirty rows in the database without data will have `data: null`
- The schema migration will automatically add the `data` column to `__dirty_rows`

### Database Schema Migration
The library's automatic migration system will:
1. Detect the missing `data` column in existing `__dirty_rows` tables
2. Add the column with `ALTER TABLE` statement
3. Existing rows will have `NULL` for the data field
4. New operations will populate the data field

### No Code Changes Required
If your sync code already checks for null before using the data field, no changes are needed:

```dart
if (dirtyRow.data != null) {
  // Use the data
}
```

## Testing

All tests pass successfully:

```
✓ insert operation captures data field
✓ update operation captures data field with only changed values
✓ delete operation stores null data
✓ data field persists across database queries
✓ data field supports various data types
✓ multiple updates on same row replace dirty row entry with latest data
```

Run the tests with:
```bash
flutter test test/dirty_row_data_test.dart
```

## Technical Implementation Details

### JSON Serialization
We use Dart's standard `jsonEncode` and `jsonDecode` functions from `dart:convert` to ensure reliable serialization of the data map. This handles:
- Primitive types (String, int, double, bool, null)
- Nested maps and lists
- Special characters and escape sequences

### Database Storage
The data is stored as a TEXT column in SQLite, containing JSON. Example:
```sql
INSERT INTO __dirty_rows (table_name, row_id, hlc, is_full_row, data)
VALUES ('c_work_order', 'some-id', '1234567890', 1, '{"rowstate":"WorkStarted"}')
```

### Memory Efficiency
- The data field is only populated when necessary
- Delete operations pass null to avoid storing unnecessary data
- JSON encoding is efficient for the typical small payloads

## See Also

- [Example Code](./example/dirty_row_data_example.dart) - Demonstration of the new functionality
- [Test Suite](./test/dirty_row_data_test.dart) - Comprehensive test coverage
- [Data Synchronization Docs](../docs/docs/core-library/data-synchronization.md) - Overall sync documentation
