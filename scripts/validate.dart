#!/usr/bin/env dart
// Validation script for Declarative SQLite library
// Run this script to validate that the library is working correctly after making changes

import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('=== Declarative SQLite Validation ===');
  
  try {
    // Initialize sqflite_ffi for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    
    // Test 1: Schema Creation
    print('✓ Testing schema creation...');
    final schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('email', (col) => col.unique())
          .integer('age'))
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .integer('user_id', (col) => col.notNull())
          .index('idx_user_id', ['user_id']));
    
    // Test 2: Schema SQL Generation
    print('✓ Testing SQL generation...');
    final sql = schema.toSqlScript();
    assert(sql.contains('CREATE TABLE users'));
    assert(sql.contains('CREATE TABLE posts'));
    assert(sql.contains('CREATE INDEX idx_user_id'));
    
    // Test 3: Database Migration
    print('✓ Testing database migration...');
    final database = await openDatabase(':memory:');
    final migrator = SchemaMigrator();
    
    // Validate schema first
    final errors = migrator.validateSchema(schema);
    assert(errors.isEmpty, 'Schema validation failed: $errors');
    
    // Apply migration
    await migrator.migrate(database, schema);
    
    // Test 4: Data Operations
    print('✓ Testing data access operations...');
    final dataAccess = DataAccess(database: database, schema: schema);
    
    // Insert user
    final userId = await dataAccess.insert('users', {
      'name': 'John Doe',
      'email': 'john@example.com',
      'age': 30,
    });
    assert(userId == 1, 'Expected user ID to be 1');
    
    // Insert post
    final postId = await dataAccess.insert('posts', {
      'title': 'Hello World',
      'user_id': userId,
    });
    assert(postId == 1, 'Expected post ID to be 1');
    
    // Retrieve user
    final user = await dataAccess.getByPrimaryKey('users', userId);
    assert(user != null, 'User should exist');
    assert(user!['name'] == 'John Doe', 'Name should match');
    assert(user!['email'] == 'john@example.com', 'Email should match');
    assert(user!['age'] == 30, 'Age should match');
    
    // Update user
    await dataAccess.updateByPrimaryKey('users', userId, {'age': 31});
    final updatedUser = await dataAccess.getByPrimaryKey('users', userId);
    assert(updatedUser!['age'] == 31, 'Age should be updated');
    
    // Query operations
    final allUsers = await dataAccess.getAll('users');
    assert(allUsers.length == 1, 'Should have exactly 1 user');
    
    final youngUsers = await dataAccess.getAllWhere('users', 
        where: 'age < ?', whereArgs: [35]);
    assert(youngUsers.length == 1, 'Should find 1 young user');
    
    // Count operations
    final userCount = await dataAccess.count('users');
    assert(userCount == 1, 'Should count 1 user');
    
    // Test 5: Migration Planning
    print('✓ Testing migration planning...');
    final plan = await migrator.planMigration(database, schema);
    assert(!plan.hasOperations, 'No operations should be needed for same schema');
    
    // Test 6: Bulk Operations
    print('✓ Testing bulk operations...');
    final bulkUsers = [
      {'name': 'Alice', 'email': 'alice@example.com', 'age': 25},
      {'name': 'Bob', 'email': 'bob@example.com', 'age': 28},
    ];
    final bulkResult = await dataAccess.bulkLoad('users', bulkUsers);
    assert(bulkResult.rowsInserted == 2, 'Should insert 2 users');
    assert(bulkResult.isComplete, 'Bulk load should complete');
    
    final finalCount = await dataAccess.count('users');
    assert(finalCount == 3, 'Should have 3 users total');
    
    await database.close();
    
    print('✓ All tests passed!');
    print('✓ Declarative SQLite library is working correctly.');
    print('=== Validation Complete ===');
    
  } catch (e, stackTrace) {
    print('✗ Validation failed with error: $e');
    print('Stack trace: $stackTrace');
    throw e;
  }
}