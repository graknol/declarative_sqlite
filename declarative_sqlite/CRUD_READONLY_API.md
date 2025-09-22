# CRUD vs Read-Only Records

The DeclarativeDatabase's DbRecord API intelligently differentiates between CRUD-enabled and read-only records based on the query source and developer intent.

## Overview

Records returned from database queries are automatically categorized as:

- **CRUD-Enabled**: Can be modified, saved, deleted, and reloaded
- **Read-Only**: Can only be read, cannot be modified or saved

The categorization depends on:

1. **Query source**: Table vs View
2. **Developer intent**: Using `forUpdate()` method
3. **Data requirements**: Presence of system_id and system_version

## Record Types

### Table Records (CRUD-Enabled by Default)

```dart
// Direct table queries return CRUD-enabled records
final users = await db.queryTableRecords('users');
final user = users.first;

print(user.isReadOnly);      // false
print(user.isCrudEnabled);   // true
print(user.updateTableName); // 'users'

// Full CRUD operations available
user.setValue('name', 'New Name');
await user.save();    // ✅ Works
await user.reload();  // ✅ Works  
await user.delete();  // ✅ Works
```

### View Records (Read-Only by Default)

```dart
// View queries return read-only records
final userDetails = await db.queryTableRecords('user_details_view');
final detail = userDetails.first;

print(detail.isReadOnly);      // true
print(detail.isCrudEnabled);   // false
print(detail.updateTableName); // null

// CRUD operations throw errors
detail.setValue('name', 'New');  // ❌ StateError
await detail.save();            // ❌ StateError
await detail.reload();          // ❌ StateError
await detail.delete();          // ❌ StateError
```

## forUpdate() Method

The `forUpdate()` method enables CRUD operations on complex queries by specifying the target table for updates:

```dart
// Enable CRUD for view/join queries
final results = await db.queryRecords(
  (q) => q.from('user_details_view')
      .forUpdate('users'), // Target 'users' table for CRUD
);

final result = results.first;
print(result.isReadOnly);      // false
print(result.isCrudEnabled);   // true  
print(result.updateTableName); // 'users'

// Can modify columns that exist in target table
result.setValue('name', 'Updated Name');
result.setValue('email', 'new@example.com');
await result.save(); // Updates the 'users' table
```

### forUpdate() Requirements

When using `forUpdate('table_name')`, the query **must include**:

1. **system_id** from the target table
2. **system_version** from the target table

```dart
// ✅ Valid forUpdate query
final validResults = await db.queryRecords(
  (q) => q.from('complex_view')
      .select('users.system_id')      // Required
      .select('users.system_version') // Required
      .select('users.name')
      .select('other_table.description')
      .forUpdate('users'),
);

// ❌ Missing required columns
final invalidResults = await db.queryRecords(
  (q) => q.from('complex_view')
      .select('users.name')           // Missing system_id & system_version
      .forUpdate('users'),            // Throws StateError
);
```

### Column Validation

Only columns that exist in the target table can be modified:

```dart
final results = await db.queryRecords(
  (q) => q.from('users')
      .select('users.system_id')
      .select('users.system_version')
      .select('users.name')
      .select('profiles.description')  // From joined table
      .leftJoin('profiles', 'profiles.user_id = users.id')
      .forUpdate('users'),
);

final result = results.first;

// ✅ Can modify users table columns
result.setValue('name', 'New Name');

// ❌ Cannot modify other table columns
result.setValue('description', 'New Desc'); // ArgumentError
```

## Reload Functionality

CRUD-enabled records can be reloaded to refresh their data from the database:

```dart
final user = (await db.queryTableRecords('users')).first;

// Modify in memory
user.setValue('name', 'Temporary Name');
print(user.getValue<String>('name')); // "Temporary Name"
print(user.modifiedFields);           // ['name']

// Reload fresh data
await user.reload();
print(user.getValue<String>('name')); // Original name restored
print(user.modifiedFields);           // [] (cleared)
```

### Reload Requirements

- **CRUD-enabled only**: `isCrudEnabled` must be true
- **Must have system_id**: For unique identification
- **Record must exist**: In the database

```dart
// ❌ Read-only records cannot be reloaded
final viewRecord = (await db.queryTableRecords('some_view')).first;
await viewRecord.reload(); // StateError

// ❌ Records without system_id cannot be reloaded
final newRecord = RecordFactory.fromTable({'name': 'Test'}, 'users', db);
await newRecord.reload(); // StateError
```

## Complex Examples

### Join Query with Update Capability

```dart
// Complex join that can update the users table
final results = await db.queryRecords(
  (q) => q.from('users')
      .select('users.system_id')        // Required for CRUD
      .select('users.system_version')   // Required for CRUD
      .select('users.name')
      .select('users.email')
      .select('profiles.description')   // Read-only joined data
      .select('profiles.website')       // Read-only joined data
      .leftJoin('profiles', 'profiles.user_id = users.id')
      .where(col('users.active').eq(true))
      .forUpdate('users'),              // Enable CRUD for users
);

final result = results.first;

// Can read all data
print('Name: ${result.getValue<String>('name')}');
print('Description: ${result.getRawValue('description')}');
print('Website: ${result.getRawValue('website')}');

// Can modify and save users table data
result.setValue('name', 'Updated Name');
result.setValue('email', 'updated@example.com');
await result.save(); // Updates users table only

// Cannot modify joined table data
result.setValue('description', 'New desc'); // ❌ ArgumentError
```

### Streaming with CRUD Support

```dart
// Different stream types with different capabilities

// 1. Table stream - CRUD-enabled
final userStream = db.streamRecords((q) => q.from('users'));
userStream.listen((users) {
  for (final user in users) {
    print('CRUD-enabled: ${user.isCrudEnabled}');
    user.setValue('last_seen', DateTime.now());
    user.save(); // ✅ Works
  }
});

// 2. View stream - read-only
final viewStream = db.streamRecords((q) => q.from('user_summary_view'));
viewStream.listen((summaries) {
  for (final summary in summaries) {
    print('Read-only: ${summary.isReadOnly}');
    // summary.setValue('name', 'Test'); // ❌ Would throw
  }
});

// 3. forUpdate stream - CRUD-enabled for target table
final updateStream = db.streamRecords(
  (q) => q.from('user_summary_view').forUpdate('users'),
);
updateStream.listen((summaries) {
  for (final summary in summaries) {
    print('Can update users: ${summary.isCrudEnabled}');
    summary.setValue('name', 'Updated');
    summary.save(); // ✅ Updates users table
  }
});
```

## Error Handling

### Clear Error Messages

```dart
// Read-only record modification
viewRecord.setValue('name', 'Test');
// StateError: Cannot modify read-only record from user_details_view

// Missing system_id for forUpdate
db.queryRecords((q) => q.from('users').select('name').forUpdate('users'));
// StateError: Query with forUpdate('users') must include system_id column

// Missing system_version for forUpdate  
db.queryRecords((q) => q.from('users').select('system_id').forUpdate('users'));
// StateError: Query with forUpdate('users') must include system_version column

// Invalid target table
db.queryRecords((q) => q.from('users').forUpdate('nonexistent'));
// ArgumentError: Update table nonexistent not found in schema

// Invalid column modification
result.setValue('nonexistent_column', 'value');
// ArgumentError: Column nonexistent_column does not exist in update table users

// Reload on read-only record
viewRecord.reload();
// StateError: Cannot reload read-only record from user_details_view
```

## Best Practices

1. **Use table queries for simple CRUD**: They're automatically CRUD-enabled
2. **Use forUpdate() sparingly**: Only when you need CRUD on complex queries
3. **Always include system columns**: When using forUpdate()
4. **Validate CRUD capability**: Check `isCrudEnabled` in generic code
5. **Handle read-only gracefully**: Provide appropriate UI feedback
6. **Use reload() for fresh data**: When external changes are expected

## Performance Considerations

- **Automatic detection**: No overhead for determining CRUD capability
- **Lazy validation**: forUpdate() requirements only validated when used
- **Efficient reloads**: Only fetch data for the specific record
- **Minimal memory**: Same underlying data structure regardless of type

## Migration from Previous API

The previous DbRecord API continues to work with enhanced behavior:

```dart
// Old code still works
final users = await db.queryRecords((q) => q.from('users'));
final user = users.first;
user.setValue('name', 'New Name');
await user.save();

// New: Check capabilities
if (user.isCrudEnabled) {
  user.setValue('name', 'New Name');
  await user.save();
} else {
  print('Record is read-only');
}

// New: forUpdate for complex queries
final results = await db.queryRecords(
  (q) => q.from('complex_view').forUpdate('users'),
);

// New: reload functionality
await user.reload();
```

This system provides complete control over record mutability while maintaining safety through validation and clear error messages.