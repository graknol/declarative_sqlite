---
sidebar_position: 1
---

# Installation

This guide will help you install and set up the Declarative SQLite packages in your Dart or Flutter project.

## Prerequisites

- **Dart SDK**: 3.5.3 or later
- **Flutter SDK**: 3.10.0 or later (for Flutter package)

## Package Selection

Choose the packages you need based on your project type:

### For Dart Projects
```yaml
dependencies:
  declarative_sqlite: ^1.0.1

dev_dependencies:
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.7
```

### For Flutter Projects
```yaml
dependencies:
  declarative_sqlite: ^1.0.1
  declarative_sqlite_flutter: ^1.0.0

dev_dependencies:
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.7
```

## Installation Steps

### 1. Add Dependencies

Add the packages to your `pubspec.yaml` file based on your project type above.

### 2. Install Packages

Run the following command to install the packages:

```bash
# For Dart projects
dart pub get

# For Flutter projects
flutter pub get
```

### 3. Import the Library

In your Dart files, import the packages:

```dart
// Core library (always needed)
import 'package:declarative_sqlite/declarative_sqlite.dart';

// Flutter widgets (Flutter projects only)
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
```

## Platform-Specific Setup

### Flutter Projects

For Flutter projects, no additional setup is required. The package automatically handles platform-specific database implementations.

### Dart Console/Server Projects

For pure Dart projects, you'll need to initialize the SQLite implementation:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // Initialize SQLite FFI for desktop/server
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  // Your application code here
}
```

## Verify Installation

Create a simple test to verify your installation:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() async {
  // Create a simple schema
  final schema = SchemaBuilder()
    .table('test', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('name', (col) => col.notNull()));
  
  // Initialize database
  final database = await DeclarativeDatabase.init(
    path: ':memory:',
    schema: schema,
  );
  
  print('✅ Declarative SQLite installed successfully!');
  await database.close();
}
```

## Next Steps

Now that you have Declarative SQLite installed, you can:

- Follow the [Quick Start Guide](./quick-start) to build your first database
- Learn about [Schema Definition](../core-library/schema-definition)
- Explore [Flutter Integration](../flutter/installation) for mobile apps

## Troubleshooting

### Common Issues

**Issue**: `dart pub get` fails with dependency conflicts
**Solution**: Ensure you're using compatible versions. Check the [compatibility matrix](./project-structure#version-compatibility).

**Issue**: SQLite errors on desktop platforms
**Solution**: Make sure you've initialized SQLite FFI as shown in the Dart console setup section.

**Issue**: Flutter build fails on specific platforms
**Solution**: Check platform-specific requirements in the [Flutter setup guide](../flutter/installation).

For more troubleshooting tips, see our [Troubleshooting Guide](../advanced/troubleshooting).