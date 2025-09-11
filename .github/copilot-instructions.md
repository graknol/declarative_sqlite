# Declarative SQLite Development Instructions

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

This is a Dart package that provides a declarative approach to SQLite schema management and data access. The library implements a fluent builder pattern for defining database schemas and automatically handles migrations and CRUD operations.

## Working Effectively

### Prerequisites and Setup
- Install Dart SDK 3.5.3 or later:
  - Download: `wget -O /tmp/dart-sdk.zip https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip`
  - Install: `cd /tmp && unzip -q dart-sdk.zip && sudo mv dart-sdk /opt/`
  - Add to PATH: `export PATH="/opt/dart-sdk/bin:$PATH"`
  - Verify: `dart --version`

### Build and Test Commands (FAST EXECUTION)
- Install dependencies: `dart pub get` -- takes 3-4 seconds. NEVER CANCEL.
- Run all tests: `dart test` -- takes 6-8 seconds total. NEVER CANCEL.
- Run specific test: `dart test test/integration_test.dart` -- takes 1-2 seconds. NEVER CANCEL.
- Run linter: `dart analyze` -- takes 2-3 seconds. NEVER CANCEL.
- Validate library functionality: `dart scripts/validate.dart` -- takes 1 second. NEVER CANCEL.

**IMPORTANT**: This is a pure Dart library with very fast build and test times. All commands complete in seconds, not minutes. Use short timeouts (60 seconds max) for all operations.

### Validation
- ALWAYS run `dart pub get && dart test` after making changes to core library code.
- ALWAYS run the validation scenario below to ensure your changes work correctly.
- ALWAYS run `dart analyze` before finalizing changes to catch linting issues.
- The build process is simple - no compilation or complex setup required.

#### Validation Scenario
After making changes, run this complete scenario to verify functionality:
```bash
dart scripts/validate.dart
```
This script:
1. Creates a schema with tables, columns, constraints, indices
2. Applies schema to in-memory database using SchemaMigrator  
3. Uses DataAccess for insert/retrieve/update operations
4. Tests bulk operations and migration planning
5. Verifies all operations work correctly

Should print success messages and complete in ~1 second.

## Project Structure

### Key Directories
- `lib/src/`: Core library implementation
  - `schema_builder.dart`: Main entry point for defining schemas
  - `table_builder.dart`: Individual table structure definitions  
  - `migrator.dart`: Database migration and validation logic
  - `data_access.dart`: Type-safe CRUD operations and bulk loading
  - `view_builder.dart`: SQL views support
- `test/`: Comprehensive test suite with integration tests
- `example/`: Example usage (some API compatibility issues exist)
- `.github/`: GitHub workflows and documentation

### Core Components
1. **SchemaBuilder**: Main entry point for defining database schemas
2. **TableBuilder**: Defines individual table structures with columns and indices
3. **ColumnBuilder**: Specifies column properties, constraints, and data types
4. **SchemaMigrator**: Handles database migration and validation
5. **DataAccess**: Provides type-safe CRUD operations and bulk data loading

## Common Development Tasks

### Creating Schemas
```dart
final schema = SchemaBuilder()
  .table('users', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('name', (col) => col.notNull())
      .text('email', (col) => col.unique())
      .integer('age')
      .index('idx_email', ['email']));
```

### Running Tests
- Full test suite: `dart test` (6-8 seconds)
- Integration tests: `dart test test/integration_test.dart` (1-2 seconds)
- Data access tests: `dart test test/data_access_test.dart` (1-2 seconds)  
- View builder tests: `dart test test/view_builder_test.dart` (1-2 seconds)

### Adding New Features
1. Write tests first in appropriate test file (`test/*_test.dart`)
2. Implement feature in `lib/src/` following immutable builder pattern
3. Run `dart test` to verify all tests pass
4. Run `dart analyze` to check code quality
5. Test with `dart test/validate_example.dart` for integration validation

## Known Issues and Workarounds

### Current Issues
- Some example files (`example/`) have API compatibility issues - avoid using as reference
- Relationship features (`test/relationship_test.dart`) have parameter naming issues in progress
- View API has some deprecated methods - use `ViewBuilder.create()` pattern

### Working Areas
- Core schema definition (SchemaBuilder, TableBuilder) - fully functional
- Database migration (SchemaMigrator) - fully functional  
- Data access operations (DataAccess) - fully functional
- Basic view support (ViewBuilder) - core functionality works

## Build Troubleshooting

If you encounter issues:
1. Ensure Dart SDK 3.5.3+ is installed: `dart --version`
2. Clean and reinstall dependencies: `dart pub get`
3. Run tests to check current state: `dart test`
4. Check for linting issues: `dart analyze`

The library has no complex build dependencies - if basic Dart commands work, the library should work.

## API Reference Quick Start

### Basic Usage Pattern
```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 1. Initialize for testing
sqfliteFfiInit();
databaseFactory = databaseFactoryFfi;

// 2. Define schema  
final schema = SchemaBuilder()
  .table('tablename', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('column1', (col) => col.notNull())
      .integer('column2'));

// 3. Apply to database
final database = await openDatabase(':memory:');
final migrator = SchemaMigrator();
await migrator.migrate(database, schema);

// 4. Use data access
final dataAccess = DataAccess(database: database, schema: schema);
final id = await dataAccess.insert('tablename', {'column1': 'value'});
final row = await dataAccess.getByPrimaryKey('tablename', id);
```

This pattern works for all core functionality and is the foundation for any development work.

## Common Files and Commands Reference

### Repository Root Structure
```
declarative_sqlite/
├── .github/                 # GitHub workflows and documentation
├── .gitignore
├── CHANGELOG.md
├── LICENSE
├── README.md               # Main project documentation
├── analysis_options.yaml  # Dart linter configuration
├── pubspec.yaml           # Project dependencies and metadata
├── lib/
│   ├── declarative_sqlite.dart  # Main library export
│   └── src/               # Core implementation
│       ├── schema_builder.dart
│       ├── table_builder.dart
│       ├── migrator.dart
│       ├── data_access.dart
│       └── view_builder.dart
├── test/                  # Test files
│   ├── integration_test.dart
│   ├── data_access_test.dart
│   └── view_builder_test.dart
├── example/               # Usage examples (some API issues)
└── scripts/               # Utility scripts
    └── validate.dart      # Library validation script
```

### Dependencies from pubspec.yaml
```yaml
dependencies:
  sqflite_common: ^2.5.4+3
  path: ^1.8.0
  meta: ^1.11.0

dev_dependencies:
  lints: ^4.0.0
  test: ^1.24.0
  sqflite_common_ffi: ^2.3.4+4  # For testing
```

### Frequently Used Commands Output
```bash
# dart --version
Dart SDK version: 3.9.3 (stable)

# dart pub get (fast - 3-4 seconds)
Resolving dependencies... 
+ 54 dependencies installed

# dart test (fast - 6-8 seconds total)
✅ 90 tests passed, 1 failed (relationship test has issues)

# dart analyze (fast - 2-3 seconds)
Shows linting issues but core functionality works
```
