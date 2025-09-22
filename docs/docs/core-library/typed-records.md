# Typed Records (DbRecord API)

Work with typed database records instead of raw `Map<String, Object?>` objects. The DbRecord API provides automatic type conversion, property-style access, and intelligent CRUD operations.

## Overview

The DbRecord API provides typed access to database records with automatic type conversion, property-style access, and intelligent CRUD operations:

```dart
// Work with typed records
final users = await db.queryTyped<User>((q) => q.from('users'));
final user = users.first;
final name = user.name; // Type-safe property access
final age = user.age;   // Nullable properties handled automatically

// Update data
user.name = 'New Name';
user.age = 30;
await user.save(); // Intelligent CRUD operations
```

## Generated Typed Record Classes

Use the code generator to create typed record classes:

### 1. Setup Code Generation

Add the generator to your `pubspec.yaml`:

```yaml
dev_dependencies:
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.0
```

### 2. Define Your Models

Create a model file (e.g., `lib/models/user.dart`):

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'user.g.dart'; // Generated code will be here

@GenerateDbRecord('users')
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);

  // The generator creates all getters and setters automatically
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
}
```

### 3. Run Code Generation

```bash
dart run build_runner build
```

This generates typed properties like:

```dart
// Generated getters (read-only properties)
int get id => getIntegerNotNull('id');
String get name => getTextNotNull('name');
String? get email => getText('email');
DateTime? get birthDate => getDateTime('birth_date');
FilesetField? get avatar => getFilesetField('avatar');

// Generated setters (modifiable properties)
set name(String value) => setText('name', value);
set email(String? value) => setText('email', value);
set birthDate(DateTime? value) => setDateTime('birth_date', value);
set avatar(FilesetField? value) => setFilesetField('avatar', value);
```

## Type Conversion

DbRecord automatically handles type conversion between Dart types and SQLite storage:

### String Values
```dart
String name = user.name;           // getTextNotNull()
String? email = user.email;        // getText()

user.name = 'Alice';               // setText()
user.email = null;                 // setText()
```

### Numeric Values
```dart
int id = user.id;                  // getIntegerNotNull()
int? score = user.score;           // getInteger()
double? rating = user.rating;      // getReal()

user.score = 100;                  // setInteger()
user.rating = 4.5;                 // setReal()
```

### DateTime Values
```dart
DateTime? createdAt = user.createdAt;   // getDateTime() - automatic ISO string parsing
DateTime? updatedAt = user.updatedAt;   

user.createdAt = DateTime.now();        // setDateTime() - automatic ISO string serialization
```

### File Attachments
```dart
FilesetField? avatar = user.avatar;     // getFilesetField()

user.avatar = FilesetField.create();    // setFilesetField()
```

## Factory Registry System

Register your record types once at application startup to eliminate mapper parameters:

### 1. Register Factories

```dart
void main() {
  // Register all your record types once
  RecordMapFactoryRegistry.register<User>(User.fromMap);
  RecordMapFactoryRegistry.register<Post>(Post.fromMap);
  RecordMapFactoryRegistry.register<Comment>(Comment.fromMap);
  
  runApp(MyApp());
}
```

### 2. Use Typed Query Methods

```dart
// No mapper parameter needed!
final users = await db.queryTyped<User>((q) => q.from('users'));
final posts = await db.queryTyped<Post>((q) => q.from('posts'));

// Works with table queries too
final activeUsers = await db.queryTableTyped<User>('users', 
  where: 'active = ?', 
  whereArgs: [true]
);

// And streaming queries
final userStream = db.streamTyped<User>((q) => q.from('users'));
```

## CRUD vs Read-Only Intelligence

Records are automatically categorized based on their source:

### Table Records (CRUD-Enabled)

```dart
// Direct table queries return CRUD-enabled records
final users = await db.queryTableTyped<User>('users');
final user = users.first;

print(user.isReadOnly);      // false
print(user.isCrudEnabled);   // true

// Full CRUD operations available
user.name = 'Updated Name';
await user.save();           // ✅ Works
await user.delete();         // ✅ Works
await user.reload();         // ✅ Works
```

### View Records (Read-Only by Default)

```dart
// View queries return read-only records
final userStats = await db.queryTyped<UserStats>((q) => q.from('user_stats_view'));
final stats = userStats.first;

print(stats.isReadOnly);     // true
print(stats.isCrudEnabled);  // false

// Only reading is allowed
final count = stats.postCount;  // ✅ Works
stats.postCount = 100;          // ❌ Throws exception
await stats.save();             // ❌ Throws exception
```

### Force CRUD for Complex Queries

```dart
// Use forUpdate() to enable CRUD for complex queries
final users = await db.queryTyped<User>((q) => 
  q.from('users u')
   .join('posts p', 'p.user_id = u.id')
   .where('p.created_at > ?', [DateTime.now().subtract(Duration(days: 7))])
   .forUpdate('users') // Enable CRUD operations targeting 'users' table
);

final user = users.first;
print(user.isCrudEnabled);  // true
user.name = 'Updated';
await user.save();          // ✅ Works - updates 'users' table
```

## Record Lifecycle

### Creating New Records

```dart
// Create a new record
final newUser = User.create(db);
newUser.name = 'Alice';
newUser.email = 'alice@example.com';
await newUser.save(); // INSERT operation
```

### Updating Existing Records

```dart
// Load and modify existing record
final user = await db.queryTyped<User>((q) => 
  q.from('users').where('id = ?', [userId])
).then((users) => users.first);

user.email = 'newemail@example.com';
await user.save(); // UPDATE operation (only modified fields)
```

### Dirty Field Tracking

DbRecord tracks which fields have been modified:

```dart
final user = users.first;
print(user.isDirty);        // false
print(user.dirtyFields);    // {}

user.name = 'New Name';
user.email = 'new@email.com';

print(user.isDirty);        // true
print(user.dirtyFields);    // {'name', 'email'}

await user.save(); // Only name and email are updated in the database

print(user.isDirty);        // false (reset after save)
print(user.dirtyFields);    // {}
```

### Reloading Data

```dart
// Reload data from database (discards local changes)
await user.reload();
```

### Deleting Records

```dart
// Delete the record
await user.delete();
```

## LWW (Last-Write-Wins) Support

DbRecord automatically handles Last-Write-Wins columns for conflict resolution:

```dart
// LWW columns are automatically managed
final user = users.first;
print(user.systemVersion); // Current version

user.name = 'Updated Name';
await user.save(); 

print(user.systemVersion); // Updated version (automatically incremented)
```

## Best Practices

### 1. Register Factories at Startup

```dart
void main() {
  // Register all record factories once
  RecordMapFactoryRegistry.register<User>(User.fromMap);
  RecordMapFactoryRegistry.register<Post>(Post.fromMap);
  
  runApp(MyApp());
}
```

### 2. Use Property-Style Access

```dart
// ✅ Preferred: Direct property access
final name = user.name;
user.email = 'new@example.com';

// ❌ Avoid: Method-style access (unless you need specific control)
final name = user.getTextNotNull('name');
user.setText('email', 'new@example.com');
```

### 3. Batch Modifications

```dart
// ✅ Efficient: Modify multiple properties before saving
user.name = 'New Name';
user.email = 'new@example.com';
user.age = 30;
await user.save(); // Single database update

// ❌ Inefficient: Multiple save operations
user.name = 'New Name';
await user.save();
user.email = 'new@example.com';
await user.save();
user.age = 30;
await user.save();
```

### 4. Handle Read-Only Records

```dart
// Check if record supports CRUD before attempting modifications
if (user.isCrudEnabled) {
  user.name = 'Updated Name';
  await user.save();
} else {
  // Handle read-only record appropriately
  showMessage('This record cannot be modified');
}
```

## Performance

- **Zero-copy wrapping**: Generated classes wrap the original Map without copying data
- **Lazy conversion**: Type conversion only happens when properties are accessed
- **Efficient updates**: Only modified fields are sent to the database
- **Optimized queries**: Factory registry eliminates reflection overhead

## Next Steps

Now that you understand typed records, explore:

- [Exception Handling](exception-handling) - Smart error handling for database operations
- [Advanced Features](advanced-features) - Garbage collection and other utilities
- [Streaming Queries](streaming-queries) - Real-time data updates with typed records