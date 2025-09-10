import 'package:declarative_sqlite/declarative_sqlite.dart';
// Note: To run this example with actual database operations, you would need:
// import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('=== Declarative SQLite Example ===\n');
  
  // Define a comprehensive database schema
  final schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('username', (col) => col.notNull().unique())
          .text('email', (col) => col.notNull())
          .text('full_name')
          .integer('age', (col) => col.withDefaultValue(0))
          .real('balance', (col) => col.withDefaultValue(0.0))
          .index('idx_username', ['username'])
          .index('idx_email', ['email']))
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .text('content')
          .integer('user_id', (col) => col.notNull())
          .integer('likes', (col) => col.withDefaultValue(0))
          .index('idx_user_id', ['user_id'])
          .index('idx_title_user', ['title', 'user_id'], unique: true))
      .table('categories', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull().unique())
          .text('description')
          .blob('icon_data')
          .index('idx_name', ['name']));

  print('Generated SQL Schema:');
  print(schema.toSqlScript());
  
  print('\n=== Schema Information ===');
  print('Tables: ${schema.tableNames.join(', ')}');
  print('Total tables: ${schema.tableCount}');

  // Show table details
  for (final tableName in schema.tableNames) {
    final table = schema.getTable(tableName)!;
    print('\nTable: $tableName');
    print('  Columns: ${table.columns.map((c) => '${c.name} (${c.dataType})').join(', ')}');
    print('  Indices: ${table.indices.map((i) => i.name).join(', ')}');
  }

  print('\n=== Data Access Layer Example ===');
  print('The DataAccess layer provides type-safe database operations:');
  
  // Show example usage (commented out since we don't have a real database here)
  print('''
// Initialize database and apply schema
final database = await openDatabase('example.db');
final migrator = SchemaMigrator();
await migrator.migrate(database, schema);

// Create data access layer
final dataAccess = DataAccess(database: database, schema: schema);

// Insert a user
final userId = await dataAccess.insert('users', {
  'username': 'alice',
  'email': 'alice@example.com',
  'full_name': 'Alice Smith',
  'age': 30,
  'balance': 150.75,
});

// Get user by primary key
final user = await dataAccess.getByPrimaryKey('users', userId);
print('User: \${user?['full_name']}');

// Update specific columns
await dataAccess.updateByPrimaryKey('users', userId, {
  'age': 31,
  'balance': 200.0,
});

// Get all users with conditions
final youngUsers = await dataAccess.getAllWhere('users', 
    where: 'age < ?', 
    whereArgs: [25],
    orderBy: 'username');

// Count users
final totalUsers = await dataAccess.count('users');

// Insert a post
final postId = await dataAccess.insert('posts', {
  'title': 'My First Post',
  'content': 'This is an amazing post about declarative SQLite!',
  'user_id': userId,
  'likes': 5,
});

// Get table metadata
final metadata = dataAccess.getTableMetadata('users');
print('Primary key: \${metadata.primaryKeyColumn}');
print('Required columns: \${metadata.requiredColumns}');
print('Unique columns: \${metadata.uniqueColumns}');

// Check if user exists
final exists = await dataAccess.existsByPrimaryKey('users', userId);

// Bulk load large datasets efficiently
final userData = [
  {
    'username': 'bob',
    'email': 'bob@example.com',
    'full_name': 'Bob Johnson',
    'age': 25,
    'balance': 75.50,
  },
  {
    'username': 'charlie',
    'email': 'charlie@example.com',
    'full_name': 'Charlie Brown',
    'age': 35,
    'balance': 300.0,
    'extra_field': 'ignored', // Extra fields are automatically filtered
  },
  {
    'username': 'diana',
    'email': 'diana@example.com',
    'full_name': 'Diana Prince',
    // Missing optional fields are handled gracefully
  },
];

final bulkResult = await dataAccess.bulkLoad('users', userData, options: BulkLoadOptions(
  batchSize: 1000,         // Process in batches of 1000 rows
  allowPartialData: true,  // Skip invalid rows instead of failing
  validateData: true,      // Validate against schema constraints
  collectErrors: true,     // Collect error details for debugging
));

print('Bulk load result:');
print('Processed: \${bulkResult.rowsProcessed}');
print('Inserted: \${bulkResult.rowsInserted}');
print('Skipped: \${bulkResult.rowsSkipped}');
if (bulkResult.errors.isNotEmpty) {
  print('Errors: \${bulkResult.errors}');
}''');

  print('\n=== Bulk Loading Features ===');
  print('The DataAccess layer supports efficient bulk loading:');
  print('• Automatic column filtering (extra columns ignored)');
  print('• Handles missing optional columns gracefully');
  print('• Batch processing for optimal performance');
  print('• Flexible error handling and validation');
  print('• Support for large datasets (tested with 5000+ rows)');
  print('• Transaction-based for data consistency');

  print('\n=== Migration Features ===');
  print('The migrator supports:');
  print('• Creating new tables and indices');
  print('• Adding indices to existing tables');  
  print('• Validation of schema integrity');
  print('• Migration planning and preview');
  
  print('\n=== Key Benefits ===');
  print('✓ Type-safe schema definition');
  print('✓ Automatic migration handling');
  print('✓ Built-in constraint validation');
  print('✓ Comprehensive CRUD operations');
  print('✓ Primary key and condition-based queries');
  print('✓ Metadata-driven operations');
  print('✓ Efficient bulk data loading with flexible validation');
}
