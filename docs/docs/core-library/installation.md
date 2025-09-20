---
sidebar_position: 1
---

# Installation

Learn how to install and set up the core `declarative_sqlite` package in your Dart or Flutter project.

## Prerequisites

- **Dart SDK**: 3.5.3 or later
- **SQLite**: 3.35 or later (automatically provided)

## Installation

### 1. Add to pubspec.yaml

Add the package to your `pubspec.yaml` file:

```yaml
dependencies:
  declarative_sqlite: ^1.0.1
  
  # For Flutter projects, also add:
  sqflite: ^2.3.4  # Provides SQLite implementation
  
dev_dependencies:
  # For code generation (optional but recommended)
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.7
```

### 2. Install the package

```bash
# For Dart projects
dart pub get

# For Flutter projects  
flutter pub get
```

### 3. Import the library

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
```

## Platform Setup

### Flutter Projects

No additional setup required! The package automatically uses:
- **sqflite** on iOS/Android
- **sqflite_common_ffi** on desktop platforms

### Pure Dart Projects

For server/console applications, initialize SQLite FFI:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // Initialize SQLite for desktop/server
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  // Your application code
  final database = await DeclarativeDatabase.init(
    path: 'app.db',
    schema: mySchema,
  );
}
```

## Verification

Test your installation with this simple example:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

Future<void> main() async {
  // Create a test schema
  final schema = SchemaBuilder()
    .table('test_table', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('name', (col) => col.notNull()));
  
  // Initialize database
  final database = await DeclarativeDatabase.init(
    path: ':memory:', // In-memory database for testing
    schema: schema,
  );
  
  // Insert test data
  await database.insert('test_table', {'name': 'Test'});
  
  // Query data
  final results = await database.query('test_table');
  print('Success! Found ${results.length} rows');
  
  await database.close();
}
```

## Configuration Options

### Database Path

```dart
// File database
final database = await DeclarativeDatabase.init(
  path: 'my_app.db',
  schema: schema,
);

// In-memory database (for testing)
final database = await DeclarativeDatabase.init(
  path: ':memory:',
  schema: schema,
);

// Custom directory
final database = await DeclarativeDatabase.init(
  path: '/path/to/custom/location/app.db',
  schema: schema,
);
```

### Migration Options

```dart
final database = await DeclarativeDatabase.init(
  path: 'app.db',
  schema: schema,
  migrationOptions: MigrationOptions(
    // Validate schema before applying changes
    validateSchema: true,
    
    // Preview migration without applying
    dryRun: false,
    
    // Custom migration callbacks
    onMigrationStart: (from, to) => print('Migrating from v$from to v$to'),
    onMigrationComplete: (from, to) => print('Migration complete'),
  ),
);
```

### Debugging Options

```dart
final database = await DeclarativeDatabase.init(
  path: 'app.db',
  schema: schema,
  options: DatabaseOptions(
    // Enable SQL query logging
    logQueries: true,
    
    // Enable detailed migration logging
    logMigrations: true,
    
    // Custom logger
    logger: (message) => print('[DB] $message'),
  ),
);
```

## Dependencies

The core package automatically manages these dependencies:

- **sqflite_common**: Cross-platform SQLite interface
- **path**: File path utilities
- **uuid**: Unique identifier generation
- **crypto**: Hashing and encryption utilities
- **collection**: Additional collection utilities

## Next Steps

Now that you have the core package installed:

1. **[Define Your Schema](./schema-definition)** - Learn how to create database schemas
2. **[Database Operations](./database-operations)** - Master CRUD operations
3. **[Streaming Queries](./streaming-queries)** - Build reactive applications
4. **[Code Generation](../generator/setup)** - Generate type-safe data classes

## Troubleshooting

### Common Issues

**Error**: `MissingPluginException` on Flutter
**Solution**: Make sure you have `sqflite` in your dependencies for Flutter projects.

**Error**: `DatabaseException: database is locked`
**Solution**: Ensure you're properly closing database connections and not opening multiple instances.

**Error**: Platform not supported  
**Solution**: Add platform-specific SQLite implementations as shown in the platform setup section.

For more help, see the [Troubleshooting Guide](../advanced/troubleshooting).