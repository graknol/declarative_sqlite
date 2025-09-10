import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Example demonstrating relationship modeling without foreign keys
/// 
/// This example shows how to:
/// 1. Define relationships between tables
/// 2. Use cascading deletes to maintain referential integrity
/// 3. Navigate relationships with proxy queries
/// 4. Manage many-to-many relationships
void main() async {
  // Initialize sqflite_ffi for standalone Dart apps
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Define a blog schema with relationships
  final schema = SchemaBuilder()
      // Users table
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('username', (col) => col.notNull().unique())
          .text('email', (col) => col.notNull())
          .text('display_name'))
      
      // Categories table  
      .table('categories', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull().unique())
          .text('description'))
      
      // Posts table
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .text('content')
          .integer('user_id', (col) => col.notNull())
          .date('published_at'))
      
      // Comments table  
      .table('comments', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('content', (col) => col.notNull())
          .integer('post_id', (col) => col.notNull())
          .integer('user_id', (col) => col.notNull())
          .date('created_at'))
      
      // Junction table for many-to-many post-categories relationship
      .table('post_categories', (table) => table
          .autoIncrementPrimaryKey('id')
          .integer('post_id', (col) => col.notNull())
          .integer('category_id', (col) => col.notNull()))
      
      // Define relationships (no database foreign keys required!)
      .oneToMany('users', 'posts',
          parentColumn: 'id',
          childColumn: 'user_id',
          onDelete: CascadeAction.cascade)
      
      .oneToMany('users', 'comments', 
          parentColumn: 'id',
          childColumn: 'user_id',
          onDelete: CascadeAction.cascade)
      
      .oneToMany('posts', 'comments',
          parentColumn: 'id', 
          childColumn: 'post_id',
          onDelete: CascadeAction.cascade)
      
      .manyToMany('posts', 'categories', 'post_categories',
          parentColumn: 'id',
          childColumn: 'id', 
          junctionParentColumn: 'post_id',
          junctionChildColumn: 'category_id',
          onDelete: CascadeAction.cascade);

  // Create database and apply schema
  final database = await openDatabase(':memory:');
  final migrator = SchemaMigrator();
  await migrator.migrate(database, schema);
  
  // Create relationship-aware data access layer
  final dataAccess = RelatedDataAccess(database: database, schema: schema);

  print('=== Relationship Modeling Example ===\n');

  // Insert sample data
  print('1. Creating sample data...');
  
  final userId = await dataAccess.insert('users', {
    'username': 'alice',
    'email': 'alice@example.com', 
    'display_name': 'Alice Smith',
  });
  
  final category1Id = await dataAccess.insert('categories', {
    'name': 'Technology',
    'description': 'Posts about technology',
  });
  
  final category2Id = await dataAccess.insert('categories', {
    'name': 'Programming', 
    'description': 'Programming tutorials and tips',
  });
  
  final postId = await dataAccess.insert('posts', {
    'title': 'Getting Started with Dart',
    'content': 'Dart is a great language for...',
    'user_id': userId,
    'published_at': DateTime.now(),
  });
  
  await dataAccess.insert('comments', {
    'content': 'Great post! Very helpful.',
    'post_id': postId,
    'user_id': userId, 
    'created_at': DateTime.now(),
  });
  
  await dataAccess.insert('comments', {
    'content': 'Looking forward to more content like this.',
    'post_id': postId,
    'user_id': userId,
    'created_at': DateTime.now(),
  });

  print('Sample data created successfully.\n');

  // Demonstrate relationship navigation
  print('2. Navigating relationships without manual joins...');
  
  // Get all posts by a user (one-to-many relationship)
  final userPosts = await dataAccess.getRelated('users', 'posts', userId);
  print('User has ${userPosts.length} posts:');
  for (final post in userPosts) {
    print('  - ${post['title']}');
  }
  print("");
  
  // Get all comments on a post (one-to-many relationship)
  final postComments = await dataAccess.getRelated('posts', 'comments', postId);
  print('Post has ${postComments.length} comments:');
  for (final comment in postComments) {
    print('  - ${comment['content']}');
  }
  print("");

  // Demonstrate many-to-many relationships
  print('3. Managing many-to-many relationships...');
  
  // Link post to categories
  await dataAccess.linkManyToMany('posts', 'categories', 'post_categories', postId, category1Id);
  await dataAccess.linkManyToMany('posts', 'categories', 'post_categories', postId, category2Id);
  
  // Get categories for a post
  final postCategories = await dataAccess.getRelated('posts', 'categories', postId, junctionTable: 'post_categories');
  print('Post is in ${postCategories.length} categories:');
  for (final category in postCategories) {
    print('  - ${category['name']}: ${category['description']}');
  }
  print("");

  // Demonstrate cascading deletes
  print('4. Cascading delete example...');
  
  // Count records before deletion
  final initialUserCount = await dataAccess.count('users');
  final initialPostCount = await dataAccess.count('posts');
  final initialCommentCount = await dataAccess.count('comments');
  final initialJunctionCount = await dataAccess.count('post_categories');
  
  print('Before deletion:');
  print('  Users: $initialUserCount');
  print('  Posts: $initialPostCount');
  print('  Comments: $initialCommentCount');
  print('  Post-Category links: $initialJunctionCount');
  print("");
  
  // Delete user with all related data
  final deletedCount = await dataAccess.deleteWithChildren('users', userId);
  print('Cascade delete removed $deletedCount total records');
  print("");
  
  // Verify cascading deletion worked
  final finalUserCount = await dataAccess.count('users');
  final finalPostCount = await dataAccess.count('posts');
  final finalCommentCount = await dataAccess.count('comments');
  final finalJunctionCount = await dataAccess.count('post_categories');
  
  print('After cascade deletion:');
  print('  Users: $finalUserCount (was $initialUserCount)');
  print('  Posts: $finalPostCount (was $initialPostCount)');
  print('  Comments: $finalCommentCount (was $initialCommentCount)');
  print('  Post-Category links: $finalJunctionCount (was $initialJunctionCount)');
  print("");

  // Demonstrate restrict cascade behavior
  print('5. Demonstrating cascade restrictions...');
  
  // Create schema with restrict behavior
  final restrictSchema = SchemaBuilder()
      .table('departments', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull()))
      .table('employees', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .integer('department_id', (col) => col.notNull()))
      .oneToMany('departments', 'employees',
          parentColumn: 'id',
          childColumn: 'department_id', 
          onDelete: CascadeAction.restrict);

  // Apply the restrict schema to a new database
  final restrictDb = await openDatabase(':memory:');
  await migrator.migrate(restrictDb, restrictSchema);
  final restrictDataAccess = RelatedDataAccess(database: restrictDb, schema: restrictSchema);
  
  // Insert test data
  final deptId = await restrictDataAccess.insert('departments', {'name': 'Engineering'});
  await restrictDataAccess.insert('employees', {'name': 'John', 'department_id': deptId});
  
  try {
    // This should fail due to restrict cascade
    await restrictDataAccess.deleteWithChildren('departments', deptId);
    print('ERROR: Delete should have been blocked!');
  } catch (e) {
    print('✓ Delete correctly blocked by restrict cascade: ${e.toString().split(':')[0]}');
  }
  
  // But with force=true, it should work
  final forcedDeleteCount = await restrictDataAccess.deleteWithChildren('departments', deptId, force: true);
  print('✓ Forced delete succeeded, removed $forcedDeleteCount records');
  print("");

  // Summary
  print('=== Summary ===');
  print('✓ Defined relationships without database foreign keys');
  print('✓ Navigated relationships with proxy queries (no manual joins needed)');
  print('✓ Managed many-to-many relationships with link/unlink methods');
  print('✓ Implemented cascading deletes that follow relationship tree');
  print('✓ Enforced cascade restrictions with optional force override');
  print('\nRelationship modeling implemented successfully!');

  await database.close();
  await restrictDb.close();
}