# DbRecord: Typed Database Records

The DeclarativeDatabase now provides a comprehensive `DbRecord` API that offers typed access to database rows with automatic type conversion, setter functionality, code generation, and built-in support for LWW (Last-Write-Wins) columns.

## Overview

Instead of working with raw `Map<String, Object?>` objects from database queries, you can now use:

1. **Generic DbRecord objects** with typed `getValue<T>()` and `setValue<T>()` methods
2. **Generated typed record classes** that extend DbRecord with property-style access
3. **RecordMapFactoryRegistry** for eliminating mapper parameters from query methods
4. **Singleton HLC clock** ensuring causal ordering across the entire application

## Generated Typed Record Classes

The build system can generate typed record classes that extend DbRecord:

```dart
// Generated class for the 'users' table
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);

  // Typed getters - no getValue() calls needed!
  int get id => getIntegerNotNull('id');
  String get name => getTextNotNull('name');
  String get email => getTextNotNull('email');
  DateTime? get birthDate => getDateTime('birth_date');

  // Typed setters - direct property assignment!
  set name(String value) => setText('name', value);
  set email(String value) => setText('email', value);
  set birthDate(DateTime? value) => setDateTime('birth_date', value);

  // Factory for registry
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
}
```

### Using Generated Classes

```dart
// Register the factory once at app startup
RecordMapFactoryRegistry.register<User>(User.fromMap);

// Query with full type safety
final users = await db.queryTyped<User>((q) => q.from('users'));

// Direct property access - truly magical! 
final user = users.first;
print('Name: ${user.name}');              // No getValue needed
print('Age: ${user.age}');                // No casting needed
print('Birth: ${user.birthDate}');        // Automatic DateTime parsing

// Direct property assignment
user.name = 'New Name';                   // No setValue needed
user.birthDate = DateTime(1990, 1, 1);    // Automatic serialization
await user.save();                        // Save changes
```

## RecordMapFactoryRegistry

Eliminates the need for mapper parameters in query methods:

```dart
// Register factories at app startup
RecordMapFactoryRegistry.register<User>(User.fromMap);
RecordMapFactoryRegistry.register<Product>(Product.fromMap);

// No mapper needed with registry!
final users = await db.streamTyped<User>(
  (q) => q.from('users'),
);
```

### Registry API

```dart
// Register factory
RecordMapFactoryRegistry.register<User>(User.fromMap);

// Check if registered
bool hasFactory = RecordMapFactoryRegistry.hasFactory<User>();

// Get registered types
Set<Type> types = RecordMapFactoryRegistry.registeredTypes;

// Clear (for testing)
RecordMapFactoryRegistry.clear();
```

## Singleton HLC Clock

The HLC (Hybrid Logical Clock) is now a singleton ensuring causal ordering across the entire application:

```dart
final clock1 = HlcClock();
final clock2 = HlcClock(); 
print(identical(clock1, clock2)); // true - same instance

// All database instances use the same clock
final db1 = await DeclarativeDatabase.open('db1.sqlite', schema: schema);
final db2 = await DeclarativeDatabase.open('db2.sqlite', schema: schema);
// Both use the same HLC instance for consistent ordering
```

## New Query Methods

### Typed Query Methods (using registry)

```dart
// Query with automatic typing
Future<List<T>> queryTyped<T extends DbRecord>(QueryBuilder);
Future<List<T>> queryTableTyped<T extends DbRecord>(String table, ...);
Stream<List<T>> streamTyped<T extends DbRecord>(QueryBuilder);

// Examples
final users = await db.queryTyped<User>((q) => q.from('users'));
final products = await db.queryTableTyped<Product>('products');
final userStream = db.streamTyped<User>((q) => q.from('users'));
```

### Generic DbRecord Methods (no registry needed)

```dart
// Query returning generic DbRecord objects
Future<List<DbRecord>> queryRecords(QueryBuilder);
Future<List<DbRecord>> queryTableRecords(String table, ...);
Stream<List<DbRecord>> streamRecords(QueryBuilder);

// Examples  
final records = await db.queryRecords((q) => q.from('users'));
final name = records.first.getValue<String>('name');
```

## Type Conversion

DbRecord automatically handles conversion between database values and Dart types:

| Column Type | Dart Type | Generated Getter/Setter |
|-------------|-----------|------------------------|
| `text`, `guid` | `String` | `getText()` / `setText()` |
| `integer` | `int` | `getInteger()` / `setInteger()` |
| `real` | `double` | `getReal()` / `setReal()` |
| `date` | `DateTime` | `getDateTime()` / `setDateTime()` |
| `fileset` | `FilesetField` | `getFilesetField()` / `setFilesetField()` |

### Helper Methods

DbRecord provides helper methods for generated code:

```dart
// Nullable getters
String? getText(String column);
int? getInteger(String column);
DateTime? getDateTime(String column);

// Non-null getters (throw if null)
String getTextNotNull(String column);
int getIntegerNotNull(String column); 
DateTime getDateTimeNotNull(String column);

// Typed setters
void setText(String column, String? value);
void setInteger(String column, int? value);
void setDateTime(String column, DateTime? value);
```

## Code Generation Setup

Add the generator to your `pubspec.yaml`:

```yaml
dev_dependencies:
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.0

dependencies:
  declarative_sqlite: ^1.0.1
```

Define your minimal classes with annotations:

```dart
// Define your schema first
final schema = SchemaBuilder()
  ..table('users', (table) {
    table.integer('id').notNull(0);
    table.text('name').notNull('');
    table.text('email').notNull('');
    table.integer('age').notNull(0);
    table.date('birth_date');
    table.key(['id']).primary();
  })
  ..build();

// Then create minimal annotated record classes
@GenerateDbRecord('users')
@RegisterFactory()
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);

  // Optional: Simple redirect to generated extension
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return UserGenerated.fromMap(data, database);
  }
}
```

Run code generation:

```bash
dart run build_runner build
```

## Automatic Factory Registration

With the new `@RegisterFactory` annotation, you can automatically register all your record factories:

```dart
void main() async {
  final db = await DeclarativeDatabase.open('app.db', schema: schema);
  
  // This registers ALL classes annotated with @RegisterFactory
  registerAllFactories(db);
  
  runApp(MyApp());
}
```

No more manual registration calls:

```dart
// OLD WAY - Manual registration (no longer needed!)
RecordMapFactoryRegistry.register<User>(User.fromMap);
RecordMapFactoryRegistry.register<Post>(Post.fromMap);
RecordMapFactoryRegistry.register<Comment>(Comment.fromMap);

// NEW WAY - Automatic registration
registerAllFactories(database);  // Registers everything!
```

## Generated Code Benefits

The enhanced code generation provides several key benefits:

### 1. Minimal Boilerplate

Instead of writing manual getters and setters:

```dart
// OLD WAY - Manual implementation
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);
      
  // Manual getters
  int get id => getIntegerNotNull('id');
  String get name => getTextNotNull('name');
  String? get email => getText('email');
  
  // Manual setters  
  set name(String value) => setText('name', value);
  set email(String? value) => setText('email', value);
  
  // Manual factory
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
}
```

You just write:

```dart
// NEW WAY - Minimal class with full generation
@GenerateDbRecord('users')
@RegisterFactory()
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);
  
  // That's it! Everything else is generated:
  // - All typed getters and setters in UserGenerated extension
  // - fromMap method in UserGenerated extension
  // - Factory registration
}
```

### 2. Single Extension Approach

The generator creates one clean extension per class that contains everything:

```dart
// Generated automatically:
extension UserGenerated on User {
  // Typed getters for all table columns
  int get id => getIntegerNotNull('id');
  String get name => getTextNotNull('name');
  String get email => getTextNotNull('email');
  int get age => getIntegerNotNull('age');
  DateTime? get birthDate => getDateTime('birth_date');
  
  // Typed setters for all table columns
  set name(String value) => setText('name', value);
  set email(String value) => setText('email', value);
  set age(int value) => setInteger('age', value);
  set birthDate(DateTime? value) => setDateTime('birth_date', value);
  
  // fromMap method
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
}
```

No complex factory layers, mixins, or indirection - just one extension with everything you need.

### 3. Simple Registration

The generator creates a simple registration function that uses the generated extensions:

```dart
void registerAllFactories(DeclarativeDatabase database) {
  RecordMapFactoryRegistry.register<User>((data) => UserGenerated.fromMap(data, database));
  RecordMapFactoryRegistry.register<Post>((data) => PostGenerated.fromMap(data, database));
}
```

### 4. Direct Usage

No more forgetting to register factories or managing registration calls:

```dart
// Use generated extensions directly
final user = UserGenerated.fromMap(userData, database);

// Or use with automatic registration
registerAllFactories(database);
final users = await database.queryTyped<User>((q) => q.from('users'));

// Access properties directly
print('Name: ${user.name}');      // Generated getter
user.email = 'new@example.com';   // Generated setter
await user.save();
```

## Usage Examples

### Working with Different API Levels

```dart
// Map-based API for dynamic queries
final results = await db.query((q) => q.from('users'));
final userName = results.first['name'] as String;
final userAge = results.first['age'] as int;

// Generic DbRecord for type-safe value access
final users = await db.queryRecords((q) => q.from('users'));
final userName = users.first.getValue<String>('name');
final userAge = users.first.getValue<int>('age');

// Generated typed classes for the best developer experience
final users = await db.queryTyped<User>((q) => q.from('users'));
final userName = users.first.name;  // Direct property access!
final userAge = users.first.age;    // No casting needed!
```

## Best Practices

1. **Register factories at startup**: Call `RecordMapFactoryRegistry.register()` for all your record types in your app's main() function
2. **Use typed classes when possible**: Generated classes provide the best developer experience
3. **Singleton HLC**: The HLC clock singleton ensures proper causal ordering - don't try to create your own instances
4. **Property-style access**: Use direct property access (`user.name`) instead of method calls (`user.getValue<String>('name')`)
5. **Batch updates**: Modify multiple properties before calling `save()`

## Performance

- **Zero-copy wrapping**: Generated classes wrap the original Map without copying data
- **Lazy conversion**: Type conversion only happens when properties are accessed
- **Efficient updates**: Only modified fields are sent to the database
- **Singleton overhead**: HLC singleton adds no runtime overhead

## Example: Complete Workflow

```dart
void main() async {
  // 1. Register factories at startup
  RecordMapFactoryRegistry.register<User>(User.fromMap);
  RecordMapFactoryRegistry.register<Product>(Product.fromMap);
  
  final db = await DeclarativeDatabase.open('app.db', schema: schema);
  
  // 2. Query with full type safety
  final users = await db.queryTyped<User>(
    (q) => q.from('users').where(col('active').eq(true)),
  );
  
  // 3. Direct property access
  for (final user in users) {
    print('${user.name} is ${user.age} years old');
    
    // 4. Direct property modification
    user.lastLoginAt = DateTime.now();
    await user.save();  // Only lastLoginAt is updated
  }
  
  // 5. Streaming with typed records
  final userStream = db.streamTyped<User>((q) => q.from('users'));
  userStream.listen((users) {
    print('User count: ${users.length}');
  });
}
```

This enhanced API provides a magical developer experience with full type safety, while maintaining all the performance and flexibility of the underlying SQLite database.