/// Example demonstrating the declarative_sqlite_generator in action.
/// 
/// This example shows how to use the generator to create data classes
/// from schema definitions.
library;

import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_generator/declarative_sqlite_generator.dart';

void main() {
  print('=== Declarative SQLite Generator Example ===\n');
  
  // Example 1: Define a simple schema
  print('📝 Defining a sample schema...');
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

  // Example 2: Generate data classes
  print('🏗️  Generating data classes...');
  final generator = SchemaCodeGenerator();
  
  // Generate code for all tables in the schema
  final allTablesCode = generator.generateCode(schema, libraryName: 'generated_data');
  print('\n📄 Generated code for all tables:');
  print('=' * 50);
  print(allTablesCode);
  print('=' * 50);
  
  // Example 3: Generate code for a specific table
  final usersTable = schema.tables.firstWhere((t) => t.name == 'users');
  final usersCode = generator.generateTableCode(usersTable, libraryName: 'users_data');
  print('\n📄 Generated code for users table only:');
  print('=' * 50);
  print(usersCode);
  print('=' * 50);
  
  // Example 4: Demonstrate usage of generated classes
  print('\n🚀 Example usage of generated data classes:');
  demonstrateGeneratedClassUsage();
}

/// Demonstrates how the generated data classes would be used.
void demonstrateGeneratedClassUsage() {
  print('''
// Example usage (this would compile if the generated classes were available):

// Creating a user from a database map
final userMap = {
  'id': 1,
  'systemId': 'user-guid-123',
  'systemVersion': 'hlc-timestamp-456',
  'username': 'alice',
  'email': 'alice@example.com',
  'age': 30,
  'created_at': DateTime.now(),
};

final user = UsersData.fromMap(userMap);
print('User: \${user.username} (\${user.email})');

// Converting back to map for database storage
final mapForDatabase = user.toMap();
print('Ready for database: \$mapForDatabase');

// Creating a new user instance
final newUser = UsersData(
  id: 2,
  systemId: 'user-guid-789',
  systemVersion: 'hlc-timestamp-abc',
  username: 'bob',
  email: 'bob@example.com',
  age: 25,
  created_at: DateTime.now(),
);

// Equality comparison works
print('Users equal: \${user == newUser}'); // false

// Hash codes work for collections
final userSet = {user, newUser};
print('Unique users: \${userSet.length}'); // 2

// Generated classes are immutable and type-safe
// user.username = 'changed'; // Compile error - final field
// final badUser = UsersData(username: null); // Compile error - required field
''');
}