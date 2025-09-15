# Declarative SQLite Generator

A build generator that creates type-safe Dart data classes for interacting with table rows and view rows from `declarative_sqlite` schemas.

## Features

- **Automatic Data Class Generation**: Generate immutable data classes from `TableBuilder` and `ViewBuilder` metadata
- **Type Safety**: Proper Dart type mapping for all SQLite data types (INTEGER, REAL, TEXT, BLOB, DATE, FILESET)
- **System Column Support**: Automatically includes system columns (`systemId`, `systemVersion`) in all generated classes
- **Database Serialization**: Generated `toMap()` and `fromMap()` methods for easy database interaction
- **Null Safety**: Proper nullable/non-nullable types based on column constraints
- **Standard Object Methods**: Generated `toString()`, `hashCode`, and `==` operators
- **Immutable Classes**: All generated classes are immutable with `const` constructors
- **Build System Integration**: Works with `build_runner` for automated code generation

## Installation

Add this package as a dev dependency in your `pubspec.yaml`:

```yaml
dev_dependencies:
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.7
```

## Usage

### 1. Define Your Schema

Create a schema definition using `declarative_sqlite`:

```dart
// lib/schema.dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final schema = SchemaBuilder()
  .table('users', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('username', (col) => col.notNull().unique())
      .text('email', (col) => col.notNull())
      .integer('age')
      .date('created_at', (col) => col.notNull()))
  .table('posts', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('title', (col) => col.notNull())
      .text('content')
      .integer('user_id', (col) => col.notNull())
      .date('published_at'));
```

### 2. Generate Data Classes

Use the generator directly in your code:

```dart
import 'package:declarative_sqlite_generator/declarative_sqlite_generator.dart';

void generateDataClasses() {
  final generator = SchemaCodeGenerator();
  
  // Generate code for all tables
  final allTablesCode = generator.generateCode(schema);
  
  // Generate code for a specific table
  final usersTable = schema.tables.firstWhere((t) => t.name == 'users');
  final usersCode = generator.generateTableCode(usersTable);
  
  // Write to files as needed
  // File('lib/generated/data_classes.g.dart').writeAsStringSync(allTablesCode);
}
```

### 3. Generated Data Classes

The generator creates immutable data classes like this:

```dart
/// Data class for users table rows.
/// Generated from TableBuilder metadata.
class UsersData {
  const UsersData({
    required this.systemId,
    required this.systemVersion,
    required this.id,
    required this.username,
    required this.email,
    this.age,
    required this.created_at,
  });

  /// systemId column (TEXT)
  final String systemId;

  /// systemVersion column (TEXT)
  final String systemVersion;

  /// id column (INTEGER)
  final int id;

  /// username column (TEXT)
  final String username;

  /// email column (TEXT)
  final String email;

  /// age column (INTEGER)
  final int? age;

  /// created_at column (TEXT)
  final DateTime created_at;

  /// Converts this data object to a map for database storage.
  Map<String, dynamic> toMap() {
    return {
      'systemId': systemId,
      'systemVersion': systemVersion,
      'id': id,
      'username': username,
      'email': email,
      'age': age,
      'created_at': created_at
    };
  }

  /// Creates a data object from a database map.
  static UsersData fromMap(Map<String, dynamic> map) {
    return UsersData(
        systemId: map['systemId'] as String,
        systemVersion: map['systemVersion'] as String,
        id: map['id'] as int,
        username: map['username'] as String,
        email: map['email'] as String,
        age: map['age'] as int?,
        created_at: map['created_at'] as DateTime);
  }

  /// String representation of this data object.
  @override
  String toString() =>
      'UsersData(systemId: $systemId, systemVersion: $systemVersion, id: $id, username: $username, email: $email, age: $age, created_at: $created_at)';

  /// Hash code for this data object.
  @override
  int get hashCode {
    return systemId.hashCode ^
        systemVersion.hashCode ^
        id.hashCode ^
        username.hashCode ^
        email.hashCode ^
        age.hashCode ^
        created_at.hashCode;
  }

  /// Equality comparison for this data object.
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UsersData &&
            other.systemId == systemId &&
            other.systemVersion == systemVersion &&
            other.id == id &&
            other.username == username &&
            other.email == email &&
            other.age == age &&
            other.created_at == created_at);
  }
}
```

### 4. Using Generated Classes

```dart
// Creating from database row
final userMap = await database.query('users', where: 'id = ?', whereArgs: [1]);
final user = UsersData.fromMap(userMap.first);

// Converting to database map
final newUser = UsersData(
  systemId: generateGuid(),
  systemVersion: generateHLC(),
  id: 0, // Will be auto-generated
  username: 'alice',
  email: 'alice@example.com',
  age: 30,
  created_at: DateTime.now(),
);

await database.insert('users', newUser.toMap());

// Type-safe property access
print('User: ${user.username} (${user.email})');
print('Age: ${user.age ?? 'Not specified'}');

// Equality and hash codes work correctly
final userSet = {user, newUser};
print('Unique users: ${userSet.length}');
```

## Data Type Mapping

The generator maps SQLite data types to appropriate Dart types:

| SQLite Type | Dart Type | Notes |
|-------------|-----------|-------|
| INTEGER | `int` | |
| REAL | `double` | |
| TEXT | `String` | |
| BLOB | `List<int>` | |
| DATE | `DateTime` | Stored as TEXT in ISO8601 format |
| FILESET | `String` | Special type for file collections |

All types become nullable (`Type?`) if the column doesn't have a `notNull()` or `primaryKey()` constraint.

## System Columns

All generated data classes automatically include system columns:

- `systemId` (String): Auto-generated GUID for the row
- `systemVersion` (String): HLC timestamp for conflict resolution

These are added by the declarative_sqlite library and are included in all generated classes.

## API Reference

### SchemaCodeGenerator

Main class for generating data classes.

```dart
const SchemaCodeGenerator({
  TableDataClassGenerator tableGenerator,
  ViewDataClassGenerator viewGenerator,
});

// Generate code for all tables and views
String generateCode(SchemaBuilder schema, {String? libraryName});

// Generate code for a specific table
String generateTableCode(TableBuilder table, {String? libraryName});

// Generate code for a specific view
String generateViewCode(ViewBuilder view, SchemaBuilder schema, {String? libraryName});
```

### TableDataClassGenerator

Generates data classes for tables.

```dart
const TableDataClassGenerator();

Class generateDataClass(TableBuilder table);
```

### ViewDataClassGenerator

Generates data classes for views (read-only, no `toMap()` method).

```dart
const ViewDataClassGenerator();

Class generateDataClass(ViewBuilder view, SchemaBuilder schema);
```

## Examples

See the `example/` directory for complete examples showing:

- Basic schema definition
- Data class generation
- Usage patterns
- Integration with declarative_sqlite

## Integration with declarative_sqlite

This generator is designed to work seamlessly with the main `declarative_sqlite` library:

1. Define your schema using `SchemaBuilder`
2. Use `SchemaMigrator` to create/migrate your database
3. Generate data classes with this generator
4. Use `DataAccess` with your generated classes for type-safe database operations

```dart
// Schema definition
final schema = SchemaBuilder().table('users', (table) => /* ... */);

// Migration
final migrator = SchemaMigrator();
await migrator.migrate(database, schema);

// Data class generation
final generator = SchemaCodeGenerator();
final generatedCode = generator.generateCode(schema);

// Type-safe data access
final dataAccess = DataAccess(database: database, schema: schema);
final userMap = await dataAccess.getByPrimaryKey('users', 1);
final user = UsersData.fromMap(userMap);
```

## License

This project is licensed under the same license as the main `declarative_sqlite` library.