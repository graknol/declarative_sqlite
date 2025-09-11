import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() async {
  print('=== Testing Declarative SQLite Library ===\n');
  
  // Initialize sqflite_ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  // Create a simple schema
  final schema = SchemaBuilder()
    .table('users', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('name', (col) => col.notNull())
        .text('email', (col) => col.unique())
        .integer('age'));

  print('Schema created successfully');
  print('SQL Script:');
  print(schema.toSqlScript());
  print('');
  
  // Test with in-memory database
  final database = await openDatabase(':memory:');
  print('In-memory database opened');
  
  // Apply schema
  final migrator = SchemaMigrator();
  await migrator.migrate(database, schema);
  print('Schema migrated successfully');
  
  // Test data operations
  final dataAccess = DataAccess(database: database, schema: schema);
  
  // Insert a user
  final userId = await dataAccess.insert('users', {
    'name': 'John Doe',
    'email': 'john@example.com',
    'age': 30,
  });
  print('Inserted user with ID: $userId');
  
  // Get the user back
  final user = await dataAccess.getByPrimaryKey('users', userId);
  print('Retrieved user: $user');
  
  // Close database
  await database.close();
  print('Test completed successfully!');
}