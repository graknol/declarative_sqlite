# Declarative SQLite

A Dart package for declaratively creating SQLite tables and automatically migrating them.

## Features

- **Declarative Schema Definition**: Use a fluent builder pattern to define your database schema
- **Automatic Migration**: Create missing tables and indices automatically
- **Data Access Abstraction**: Type-safe CRUD operations with schema metadata integration
- **Bulk Data Loading**: Efficiently load large datasets with flexible validation and error handling
- **SQLite Data Types**: Full support for SQLite affinities (INTEGER, REAL, TEXT, BLOB)
- **Constraints**: Support for Primary Key, Unique, and Not Null constraints
- **Indices**: Single-column and composite indices with unique option
- **Type Safe**: Built with null safety and immutable builders

## Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  declarative_sqlite: ^1.0.0
  sqflite: ^2.3.0  # For Flutter apps
  # OR
  sqflite_common_ffi: ^2.3.0  # For standalone Dart apps
```

## Usage

### Basic Schema Definition

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final schema = SchemaBuilder()
    .table('users', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('name', (col) => col.notNull())
        .text('email', (col) => col.unique())
        .integer('age')
        .real('balance', (col) => col.withDefaultValue(0.0))
        .blob('avatar_data'))
    .table('posts', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('title', (col) => col.notNull())
        .text('content')
        .integer('user_id', (col) => col.notNull())
        .index('idx_user_id', ['user_id'])
        .index('idx_title_user', ['title', 'user_id'], unique: true));
```

### Applying Schema to Database

```dart
import 'package:sqflite/sqflite.dart';

// Open database
final database = await openDatabase('my_database.db');

// Create migrator and apply schema
final migrator = SchemaMigrator();
await migrator.migrate(database, schema);

// Your database now has the tables and indices defined in the schema
```

### Data Types

The library supports all SQLite data type affinities:

```dart
final table = TableBuilder('data_types_example')
    .integer('int_column')        // INTEGER affinity
    .real('real_column')          // REAL affinity  
    .text('text_column')          // TEXT affinity
    .blob('blob_column');         // BLOB affinity
```

### Column Constraints

```dart
final table = TableBuilder('users')
    .integer('id', (col) => col.primaryKey())
    .text('email', (col) => col.unique().notNull())
    .text('name', (col) => col.notNull())
    .integer('age', (col) => col.withDefaultValue(0));
```

### Indices

Create single-column or composite indices:

```dart
final table = TableBuilder('posts')
    .autoIncrementPrimaryKey('id')
    .text('title')
    .text('category')
    .integer('user_id')
    // Single column index
    .index('idx_user_id', ['user_id'])
    // Composite unique index
    .index('idx_title_category', ['title', 'category'], unique: true);
```

### Migration Planning

Preview what changes will be made before applying them:

```dart
final migrator = SchemaMigrator();
final plan = await migrator.planMigration(database, schema);

if (plan.hasOperations) {
    print('Tables to create: ${plan.tablesToCreate}');
    print('Indices to create: ${plan.indicesToCreate}');
    
    // Apply the migration
    await migrator.migrate(database, schema);
}
```

### Schema Validation

```dart
final migrator = SchemaMigrator();
final errors = migrator.validateSchema(schema);

if (errors.isNotEmpty) {
    print('Schema validation errors:');
    for (final error in errors) {
        print('- $error');
    }
} else {
    await migrator.migrate(database, schema);
}
```

## Data Access Layer

The library includes a comprehensive data access abstraction layer that provides type-safe database operations using your schema metadata.

### Basic CRUD Operations

```dart
// Create data access layer
final dataAccess = DataAccess(database: database, schema: schema);

// Insert a new record
final userId = await dataAccess.insert('users', {
  'name': 'Alice Smith',
  'email': 'alice@example.com',
  'age': 30,
  'balance': 150.75,
});

// Get a record by primary key
final user = await dataAccess.getByPrimaryKey('users', userId);
print('User: ${user?['name']}');

// Update specific columns by primary key
await dataAccess.updateByPrimaryKey('users', userId, {
  'age': 31,
  'balance': 200.0,
});

// Delete a record by primary key
await dataAccess.deleteByPrimaryKey('users', userId);
```

### Query Operations

```dart
// Get all records
final allUsers = await dataAccess.getAll('users', orderBy: 'name');

// Get records with conditions
final youngUsers = await dataAccess.getAllWhere('users',
    where: 'age < ?',
    whereArgs: [25],
    orderBy: 'name',
    limit: 10);

// Count records
final userCount = await dataAccess.count('users');
final activeCount = await dataAccess.count('users', 
    where: 'balance > ?', 
    whereArgs: [0]);

// Check if record exists
final exists = await dataAccess.existsByPrimaryKey('users', userId);
```

### Bulk Operations

```dart
// Update multiple records
final updatedRows = await dataAccess.updateWhere('users',
    {'status': 'active'},
    where: 'balance > ?',
    whereArgs: [0]);

// Delete multiple records
final deletedRows = await dataAccess.deleteWhere('users',
    where: 'age < ?',
    whereArgs: [18]);
```

### Bulk Data Loading

Efficiently load large datasets with automatic column filtering and validation:

```dart
final dataset = [
  {
    'name': 'John Doe',
    'email': 'john@example.com',
    'age': 25,
    'balance': 100.0,
  },
  {
    'name': 'Jane Smith',
    'email': 'jane@example.com',
    'age': 30,
    'extra_field': 'ignored', // Extra columns are automatically filtered
  },
  // ... thousands more records
];

final result = await dataAccess.bulkLoad('users', dataset, options: BulkLoadOptions(
  batchSize: 1000,         // Process in batches of 1000 rows
  allowPartialData: true,  // Skip invalid rows instead of failing
  validateData: true,      // Validate against schema constraints
  collectErrors: true,     // Collect error details for debugging
));

print('Bulk load result:');
print('Processed: ${result.rowsProcessed}');
print('Inserted: ${result.rowsInserted}');
print('Skipped: ${result.rowsSkipped}');
if (result.errors.isNotEmpty) {
  print('Errors: ${result.errors}');
}
```

The bulk loader automatically handles:
- **Column Filtering**: Extra columns in the dataset are ignored
- **Missing Columns**: Optional columns can be missing from individual rows
- **Validation**: Schema constraints are enforced (can be disabled for performance)
- **Error Handling**: Failed rows can be skipped with detailed error reporting
- **Performance**: Transaction-based batch processing for large datasets

### Schema Metadata

Access table structure information programmatically:

```dart
final metadata = dataAccess.getTableMetadata('users');
print('Primary key: ${metadata.primaryKeyColumn}');
print('Required columns: ${metadata.requiredColumns}');
print('Unique columns: ${metadata.uniqueColumns}');
print('All columns: ${metadata.columns.keys}');

// Check column properties
print('Is email required? ${metadata.isColumnRequired('email')}');
print('Is email unique? ${metadata.isColumnUnique('email')}');
print('Email data type: ${metadata.getColumnType('email')}');
```

## API Reference

### SchemaBuilder

The main entry point for defining database schemas.

- `table(String name, TableBuilder Function(TableBuilder) builder)` - Add a table to the schema
- `addTable(TableBuilder table)` - Add a pre-built table
- `toSqlScript()` - Generate complete SQL script for the schema
- `tableNames` - Get list of table names in the schema

### TableBuilder

Builder for defining table structure.

- `integer(String name, [configure])` - Add INTEGER column
- `real(String name, [configure])` - Add REAL column  
- `text(String name, [configure])` - Add TEXT column
- `blob(String name, [configure])` - Add BLOB column
- `autoIncrementPrimaryKey(String name)` - Add auto-increment primary key
- `index(String name, List<String> columns, {bool unique})` - Add single-column or composite index

### ColumnBuilder

Builder for defining column constraints.

- `primaryKey()` - Add primary key constraint
- `unique()` - Add unique constraint
- `notNull()` - Add not null constraint
- `withDefaultValue(dynamic value)` - Set default value

### SchemaMigrator

Handles database schema migration.

- `migrate(Database db, SchemaBuilder schema)` - Apply schema to database
- `planMigration(Database db, SchemaBuilder schema)` - Preview migration changes
- `validateSchema(SchemaBuilder schema)` - Validate schema definition

## Limitations

- Column modifications (ALTER COLUMN) are not supported - SQLite has limited ALTER TABLE support
- Foreign key constraints are not yet implemented
- Only additive migrations (new tables/indices) are currently supported

## Best Practices

1. **Use descriptive names**: Choose clear, consistent names for tables, columns, and indices
2. **Define constraints**: Always specify NOT NULL, UNIQUE, and PRIMARY KEY constraints where appropriate
3. **Index strategically**: Add indices on columns used in WHERE clauses and JOINs
4. **Test migrations**: Use the migration planning feature to preview changes
5. **Validate schemas**: Always validate schemas before applying to production databases

## Contributing

Contributions are welcome! Please read the contributing guidelines and submit pull requests to the GitHub repository.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
