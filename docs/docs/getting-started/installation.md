# Installation

Get started with Declarative SQLite by adding the packages to your project.

## Package Selection

Choose the packages you need based on your project type:

### For Flutter Applications

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Core database functionality
  declarative_sqlite: ^1.0.1
    
  # Flutter-specific widgets and utilities  
  declarative_sqlite_flutter: ^1.0.0
    
  # SQLite driver for Flutter
  sqflite: ^2.3.0

dev_dependencies:
  # Code generation for typed records (recommended)
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.0
```

### For Standalone Dart Applications

```yaml
dependencies:
  # Core database functionality
  declarative_sqlite: ^1.0.1
    
  # SQLite driver for Dart (non-Flutter)
  sqflite_common_ffi: ^2.3.0

dev_dependencies:
  # Code generation for typed records (recommended)
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.0
```

## Platform Setup

### Android

No additional setup required. SQLite is available by default.

### iOS

No additional setup required. SQLite is available by default.

### macOS

For Flutter desktop apps, you may need to enable network entitlements if using synchronization features:

```xml
<!-- macos/Runner/DebugProfile.entitlements -->
<key>com.apple.security.network.client</key>
<true/>
```

### Linux

For standalone Dart applications using `sqflite_common_ffi`, you may need to install SQLite:

```bash
# Ubuntu/Debian
sudo apt-get install sqlite3 libsqlite3-dev

# CentOS/RHEL
sudo yum install sqlite sqlite-devel
```

### Windows

For standalone Dart applications, SQLite should work out of the box with `sqflite_common_ffi`.

## Verification

Create a simple test to verify your installation:

### Flutter Test

```dart
// test_installation.dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

void main() {
  runApp(
    DatabaseProvider(
      schema: (builder) {
        builder.table('test', (table) {
          table.guid('id').notNull();
          table.text('name').notNull();
          table.key(['id']).primary();
        });
      },
      databaseName: 'test.db',
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Declarative SQLite is working!'),
          ),
        ),
      ),
    ),
  );
}
```

### Dart Test

```dart
// test_installation.dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // Initialize SQLite FFI for standalone Dart apps
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final database = DeclarativeDatabase(
    schema: (builder) {
      builder.table('test', (table) {
        table.guid('id').notNull();
        table.text('name').notNull();
        table.key(['id']).primary();
      });
    },
    path: 'test.db',
  );

  // Test basic operations
  await database.insert('test', {
    'id': 'test-1',
    'name': 'Test Item',
  });

  final results = await database.query('test');
  print('Installation successful! Found ${results.length} test records.');
  
  await database.close();
}
```

Run the test:

```bash
dart test_installation.dart
```

If you see "Installation successful!" then everything is working correctly.

## Next Steps

Now that you have Declarative SQLite installed, continue with:

- [Quick Start Guide](quick-start) - Learn the basics and set up typed records
- [Typed Records](../core-library/typed-records) - Work with generated typed record classes
- [Schema Definition](../core-library/schema-definition) - Design your database structure
- [Exception Handling](../core-library/exception-handling) - Handle database errors gracefully