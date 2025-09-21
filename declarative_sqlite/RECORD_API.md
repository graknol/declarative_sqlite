# DbRecord: Typed Database Records

The DeclarativeDatabase now provides a new `DbRecord` API that offers typed access to database rows with automatic type conversion, setter functionality, and built-in support for LWW (Last-Write-Wins) columns.

## Overview

Instead of working with raw `Map<String, Object?>` objects from database queries, you can now use `DbRecord` objects that provide:

- **Typed getters** with automatic type conversion
- **Typed setters** with automatic serialization  
- **LWW column handling** with automatic HLC updates
- **Dirty field tracking** for efficient updates
- **System column access** (system_id, system_created_at, etc.)

## Basic Usage

### Querying with DbRecord

```dart
// Query using the new DbRecord API
final users = await db.queryRecords(
  (q) => q.from('users').where(col('age').gt(21)),
);

// Or query a table directly
final products = await db.queryTableRecords(
  'products',
  where: 'price < ?',
  whereArgs: [100.0],
);

// Access typed values
for (final user in users) {
  final name = user.getValue<String>('name');     // No casting needed
  final age = user.getValue<int>('age');           // Automatic type conversion
  final birthDate = user.getValue<DateTime>('birth_date'); // DateTime parsing
  
  print('$name is $age years old, born on $birthDate');
}
```

### Updating Records

```dart
final user = users.first;

// Set values with automatic type conversion
user.setValue('age', 25);
user.setValue('birth_date', DateTime(1998, 3, 15)); // Auto-serialized to ISO string
user.setValue('bio', 'Updated bio');  // If 'bio' is LWW, HLC is auto-updated

// Save only the modified fields
await user.save();

// Check what was modified
print('Modified fields: ${user.modifiedFields}'); // ['age', 'birth_date', 'bio', 'bio__hlc']
```

## Type Conversion

DbRecord automatically handles conversion between database values and Dart types:

| Column Type | Dart Type | Conversion |
|-------------|-----------|------------|
| `text`, `guid` | `String` | Direct |
| `integer` | `int` | Direct |
| `real` | `double` | Direct |
| `date` | `DateTime` | Parse ISO string / timestamp |
| `fileset` | `FilesetField` | Database value ↔ FilesetField |

### DateTime Handling

```dart
// Setting DateTime values
user.setValue('created_at', DateTime.now()); // Stored as ISO string
user.setValue('timestamp', DateTime.fromMillisecondsSinceEpoch(1234567890));

// Getting DateTime values  
final createdAt = user.getValue<DateTime>('created_at'); // Parsed automatically
final timestamp = user.getValue<DateTime>('timestamp');
```

### FilesetField Support

```dart
// Setting FilesetField values
final filesetField = FilesetField.create(database, 'file-content');
user.setValue('profile_image', filesetField); // Stored as fileset ID

// Getting FilesetField values
final profileImage = user.getValue<FilesetField>('profile_image');
final content = await profileImage?.getContent();
```

## LWW (Last-Write-Wins) Columns

For columns marked as LWW in your schema, DbRecord automatically manages HLC (Hybrid Logical Clock) timestamps:

```dart
// Schema definition
table.text('description').lww(); // Mark as LWW column

// When you update an LWW column
record.setValue('description', 'New description');

// The HLC is automatically updated
print(record.getRawValue('description__hlc')); // New HLC timestamp
print(record.modifiedFields); // ['description', 'description__hlc']
```

## System Column Access

DbRecord provides convenient access to system columns:

```dart
final user = users.first;

print('System ID: ${user.systemId}');                    // system_id
print('Created: ${user.systemCreatedAt}');               // system_created_at 
print('Version: ${user.systemVersion}');                 // system_version (HLC)
```

## CRUD Operations

### Creating Records

```dart
// Create a new record (not yet in database)
final newUser = RecordFactory.fromMap({
  'name': 'Jane Doe',
  'email': 'jane@example.com',
  'age': 28,
}, 'users', database);

// Insert into database
await newUser.insert();
```

### Updating Records

```dart
// Modify and save
user.setValue('email', 'newemail@example.com');
user.setValue('age', user.getValue<int>('age')! + 1);
await user.save(); // Only modified fields are updated
```

### Deleting Records

```dart
await user.delete(); // Removes from database
```

## Streaming Queries

DbRecord works with streaming queries for real-time updates:

```dart
final userStream = db.streamRecords(
  (q) => q.from('users').where(col('active').eq(true)),
);

userStream.listen((users) {
  print('Active users count: ${users.length}');
  for (final user in users) {
    print('  ${user.getValue<String>('name')}');
  }
});
```

## Migration from Map-based API

The DbRecord API is fully compatible with the existing Map-based API:

```dart
// Old way
final results = await db.query((q) => q.from('users'));
final userName = results.first['name'] as String; // Manual casting
final userAge = results.first['age'] as int;

// New way  
final users = await db.queryRecords((q) => q.from('users'));
final userName = users.first.getValue<String>('name'); // No casting
final userAge = users.first.getValue<int>('age');

// Both APIs can be used simultaneously
```

## Error Handling

DbRecord provides helpful error messages:

```dart
try {
  user.getValue('nonexistent_column');
} catch (e) {
  print(e); // ArgumentError: Column nonexistent_column not found in table users
}

try {
  user.save(); // Without system_id
} catch (e) {
  print(e); // StateError: Cannot save record without system_id
}
```

## Performance Considerations

- **Efficient updates**: Only modified fields are sent to the database
- **Lazy conversion**: Type conversion happens only when values are accessed
- **Memory efficient**: DbRecord wraps the original Map without copying data
- **Dirty tracking**: Minimal overhead for tracking field modifications

## Best Practices

1. **Use typed getters**: Always specify the type when calling `getValue<T>()`
2. **Handle null values**: Use nullable types when columns can be null
3. **Batch updates**: Modify multiple fields before calling `save()`
4. **Stream queries**: Use `streamRecords()` for real-time data updates
5. **Error handling**: Wrap database operations in try-catch blocks

## Example: Complete User Management

```dart
class UserManager {
  final DeclarativeDatabase db;
  
  UserManager(this.db);
  
  Future<DbRecord> createUser(String name, String email, int age) async {
    final user = RecordFactory.fromMap({
      'name': name,
      'email': email,
      'age': age,
      'created_at': DateTime.now().toIso8601String(),
    }, 'users', db);
    
    await user.insert();
    return user;
  }
  
  Future<List<DbRecord>> getActiveUsers() {
    return db.queryRecords(
      (q) => q.from('users').where(col('active').eq(true)),
    );
  }
  
  Future<void> updateUserAge(String userId, int newAge) async {
    final users = await db.queryTableRecords(
      'users',
      where: 'system_id = ?',
      whereArgs: [userId],
    );
    
    if (users.isNotEmpty) {
      final user = users.first;
      user.setValue('age', newAge);
      user.setValue('updated_at', DateTime.now());
      await user.save();
    }
  }
  
  Stream<List<DbRecord>> watchUsers() {
    return db.streamRecords((q) => q.from('users'));
  }
}
```