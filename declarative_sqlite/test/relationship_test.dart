import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('Relationship Feature Tests', () {
    late Database database;
    late SchemaMigrator migrator;
    late SchemaBuilder schema;
    late DataAccess dataAccess;

    setUpAll(() {
      // Initialize sqflite_ffi for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Create an in-memory database for each test
      database = await openDatabase(inMemoryDatabasePath);
      migrator = SchemaMigrator();
      
      // Create a test schema with relationships
      schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('username', (col) => col.notNull().unique())
              .text('email', (col) => col.notNull()))
          .table('posts', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .text('content')
              .integer('user_id', (col) => col.notNull()))
          .table('categories', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull().unique()))
          .table('post_categories', (table) => table
              .autoIncrementPrimaryKey('id')
              .integer('post_id', (col) => col.notNull())
              .integer('category_id', (col) => col.notNull()))
          .table('comments', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('content', (col) => col.notNull())
              .integer('post_id', (col) => col.notNull())
              .integer('user_id', (col) => col.notNull()))
          // Define relationships
          .oneToMany('users', 'posts',
              parentColumns: ['id'], 
              childColumns: ['user_id'], 
              onDelete: CascadeAction.cascade)
          .oneToMany('posts', 'comments',
              parentColumns: ['id'], 
              childColumns: ['post_id'], 
              onDelete: CascadeAction.cascade)
          .oneToMany('users', 'comments',
              parentColumns: ['id'], 
              childColumns: ['user_id'], 
              onDelete: CascadeAction.cascade)
          .manyToMany('posts', 'categories', 'post_categories',
              parentColumns: ['id'],
              childColumns: ['id'],
              junctionParentColumns: ['post_id'],
              junctionChildColumns: ['category_id'],
              onDelete: CascadeAction.cascade);
      
      // Apply schema to database
      await migrator.migrate(database, schema);
      
      // Create data access instance
      dataAccess = await DataAccess.create(database: database, schema: schema);
    });

    tearDown(() async {
      await database.close();
    });

    group('Schema Relationship Definition', () {
      test('can define one-to-many relationships', () {
        expect(schema.relationshipCount, equals(4));
        expect(schema.hasRelationship('users', 'posts'), isTrue);
        
        final relationship = schema.getRelationship('users', 'posts');
        expect(relationship, isNotNull);
        expect(relationship!.type, equals(RelationshipType.oneToMany));
        expect(relationship.parentTable, equals('users'));
        expect(relationship.childTable, equals('posts'));
        expect(relationship.parentColumns, equals(['id']));
        expect(relationship.childColumns, equals(['user_id']));
        expect(relationship.onDelete, equals(CascadeAction.cascade));
      });

      test('can define many-to-many relationships', () {
        final relationship = schema.getRelationship('posts', 'categories', junctionTable: 'post_categories');
        expect(relationship, isNotNull);
        expect(relationship!.type, equals(RelationshipType.manyToMany));
        expect(relationship.parentTable, equals('posts'));
        expect(relationship.childTable, equals('categories'));
        expect(relationship.junctionTable, equals('post_categories'));
        expect(relationship.junctionParentColumns, equals(['post_id']));
        expect(relationship.junctionChildColumns, equals(['category_id']));
      });

      test('can query relationships by table', () {
        final userParentRels = schema.getParentRelationships('users');
        expect(userParentRels.length, equals(2));
        expect(userParentRels.map((r) => r.childTable), containsAll(['posts', 'comments']));
        
        final postChildRels = schema.getChildRelationships('posts');
        expect(postChildRels.length, equals(1));
        expect(postChildRels.first.parentTable, equals('users'));
        
        final allPostRels = schema.getTableRelationships('posts');
        expect(allPostRels.length, equals(3)); // users->posts, posts->comments, posts<->categories
      });
    });

    group('Related Data Access - One-to-Many', () {
      test('can get related children', () async {
        // Insert test data
        final userId = await dataAccess.insert('users', {
          'username': 'alice',
          'email': 'alice@example.com',
        });

        final post1Id = await dataAccess.insert('posts', {
          'title': 'First Post',
          'content': 'Content of first post',
          'user_id': userId,
        });

        final post2Id = await dataAccess.insert('posts', {
          'title': 'Second Post', 
          'content': 'Content of second post',
          'user_id': userId,
        });

        // Get related posts
        final posts = await dataAccess.getRelated('users', 'posts', userId);
        
        expect(posts.length, equals(2));
        expect(posts.map((p) => p['title']), containsAll(['First Post', 'Second Post']));
        expect(posts.every((p) => p['user_id'] == userId), isTrue);
      });

      test('can get related parents', () async {
        // Insert test data
        final userId = await dataAccess.insert('users', {
          'username': 'bob',
          'email': 'bob@example.com',
        });

        final postId = await dataAccess.insert('posts', {
          'title': 'Bob Post',
          'content': 'Bob content',
          'user_id': userId,
        });

        // Get parent user from post
        final parents = await dataAccess.getRelatedParents('users', 'posts', userId);
        
        expect(parents.length, equals(1));
        expect(parents.first['username'], equals('bob'));
        expect(parents.first['id'], equals(userId));
      });
    });

    group('Related Data Access - Many-to-Many', () {
      test('can create many-to-many links', () async {
        // Insert test data
        final userId = await dataAccess.insert('users', {
          'username': 'carol',
          'email': 'carol@example.com',
        });

        final postId = await dataAccess.insert('posts', {
          'title': 'Carol Post',
          'content': 'Carol content',
          'user_id': userId,
        });

        final category1Id = await dataAccess.insert('categories', {
          'name': 'Technology',
        });

        final category2Id = await dataAccess.insert('categories', {
          'name': 'Programming',
        });

        // Create many-to-many links
        await dataAccess.linkManyToMany('posts', 'categories', 'post_categories', postId, category1Id);
        await dataAccess.linkManyToMany('posts', 'categories', 'post_categories', postId, category2Id);

        // Get related categories
        final categories = await dataAccess.getRelated('posts', 'categories', postId, junctionTable: 'post_categories');
        
        expect(categories.length, equals(2));
        expect(categories.map((c) => c['name']), containsAll(['Technology', 'Programming']));
      });

      test('can remove many-to-many links', () async {
        // Setup test data
        final userId = await dataAccess.insert('users', {
          'username': 'dave',
          'email': 'dave@example.com',
        });

        final postId = await dataAccess.insert('posts', {
          'title': 'Dave Post',
          'content': 'Dave content', 
          'user_id': userId,
        });

        final categoryId = await dataAccess.insert('categories', {
          'name': 'Testing',
        });

        // Create and then remove link
        await dataAccess.linkManyToMany('posts', 'categories', 'post_categories', postId, categoryId);
        
        var categories = await dataAccess.getRelated('posts', 'categories', postId, junctionTable: 'post_categories');
        expect(categories.length, equals(1));

        final unlinkCount = await dataAccess.unlinkManyToMany('posts', 'categories', 'post_categories', postId, categoryId);
        expect(unlinkCount, equals(1));

        categories = await dataAccess.getRelated('posts', 'categories', postId, junctionTable: 'post_categories');
        expect(categories.length, equals(0));
      });
    });

    group('Path-based Relationship Navigation', () {
      test('can navigate through multiple relationship paths', () async {
        // Insert test data with deeper hierarchy
        final userId = await dataAccess.insert('users', {
          'username': 'alice',
          'email': 'alice@example.com',
        });

        final post1Id = await dataAccess.insert('posts', {
          'title': 'First Post',
          'content': 'Content of first post',
          'user_id': userId,
        });

        final post2Id = await dataAccess.insert('posts', {
          'title': 'Second Post', 
          'content': 'Content of second post',
          'user_id': userId,
        });

        // Add comments to posts
        await dataAccess.insert('comments', {
          'content': 'Comment on first post',
          'post_id': post1Id,
          'user_id': userId,
        });

        await dataAccess.insert('comments', {
          'content': 'Another comment on first post',
          'post_id': post1Id,
          'user_id': userId,
        });

        await dataAccess.insert('comments', {
          'content': 'Comment on second post',
          'post_id': post2Id,
          'user_id': userId,
        });

        // Direct user comments
        await dataAccess.insert('comments', {
          'content': 'Direct user comment',
          'post_id': post1Id,
          'user_id': userId,
        });

        // Test path navigation: users -> posts -> comments (comments on user's posts)
        final commentsOnUserPosts = await dataAccess.getRelatedByPath(['users', 'posts', 'comments'], userId);
        expect(commentsOnUserPosts.length, equals(4)); // All comments on user's posts
        expect(commentsOnUserPosts.every((c) => c['user_id'] == userId), isTrue);

        // Test path navigation: users -> comments (direct comments by user)
        final directUserComments = await dataAccess.getRelatedByPath(['users', 'comments'], userId);
        expect(directUserComments.length, equals(4)); // All comments by this user
        expect(directUserComments.every((c) => c['user_id'] == userId), isTrue);

        // Verify they're the same in this case (same user commenting on their own posts)
        expect(commentsOnUserPosts.length, equals(directUserComments.length));
      });

      test('throws error for invalid relationship paths', () async {
        final userId = await dataAccess.insert('users', {
          'username': 'bob',
          'email': 'bob@example.com',
        });

        // Test with non-existent relationship
        expect(
          () => dataAccess.getRelatedByPath(['users', 'nonexistent'], userId),
          throwsA(isA<ArgumentError>()),
        );

        // Test with too short path
        expect(
          () => dataAccess.getRelatedByPath(['users'], userId),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Composite Key Relationships', () {
      test('can define relationships with composite keys', () async {
        // Create schema with composite key relationships
        final compositeSchema = SchemaBuilder()
            .table('companies', (table) => table
                .text('country_code', (col) => col.notNull())
                .text('company_code', (col) => col.notNull())
                .text('name', (col) => col.notNull())
                .compositeKey(['country_code', 'company_code']))
            .table('departments', (table) => table
                .autoIncrementPrimaryKey('id')
                .text('name', (col) => col.notNull())
                .text('company_country', (col) => col.notNull())
                .text('company_code', (col) => col.notNull()))
            .oneToMany('companies', 'departments',
                parentColumns: ['country_code', 'company_code'],
                childColumns: ['company_country', 'company_code'],
                onDelete: CascadeAction.cascade);

        // Verify relationship was created correctly
        final relationship = compositeSchema.getRelationship('companies', 'departments');
        expect(relationship, isNotNull);
        expect(relationship!.parentColumns, equals(['country_code', 'company_code']));
        expect(relationship.childColumns, equals(['company_country', 'company_code']));
      });
    });

    group('Cascading Deletes', () {
      test('can delete with children - simple cascade', () async {
        // Setup test data
        final userId = await dataAccess.insert('users', {
          'username': 'eve',
          'email': 'eve@example.com',
        });

        final post1Id = await dataAccess.insert('posts', {
          'title': 'Eve Post 1',
          'content': 'Eve content 1',
          'user_id': userId,
        });

        final post2Id = await dataAccess.insert('posts', {
          'title': 'Eve Post 2',
          'content': 'Eve content 2',
          'user_id': userId,
        });

        // Add some comments
        await dataAccess.insert('comments', {
          'content': 'Great post!',
          'post_id': post1Id,
          'user_id': userId,
        });

        await dataAccess.insert('comments', {
          'content': 'Another comment',
          'post_id': post2Id,
          'user_id': userId,
        });

        // Verify initial state
        var posts = await dataAccess.getRelated('users', 'posts', userId);
        var comments = await dataAccess.getAll('comments');
        expect(posts.length, equals(2));
        expect(comments.length, equals(2));

        // Delete user with cascade
        final deletedCount = await dataAccess.deleteWithChildren('users', userId);
        
        // Should delete user, 2 posts, and 2 comments = 5 records
        expect(deletedCount, equals(5));

        // Verify all related data is gone
        posts = await dataAccess.getAll('posts');
        comments = await dataAccess.getAll('comments');
        final users = await dataAccess.getAll('users');
        
        expect(users.length, equals(0));
        expect(posts.length, equals(0));
        expect(comments.length, equals(0));
      });

      test('respects cascade restrictions', () async {
        // Create a schema with restrict cascade action
        final restrictSchema = SchemaBuilder()
            .table('parents', (table) => table
                .autoIncrementPrimaryKey('id')
                .text('name', (col) => col.notNull()))
            .table('children', (table) => table
                .autoIncrementPrimaryKey('id')
                .text('name', (col) => col.notNull())
                .integer('parent_id', (col) => col.notNull()))
            .oneToMany('parents', 'children',
                parentColumns: ['id'],
                childColumns: ['parent_id'],
                onDelete: CascadeAction.restrict);

        // Apply schema and create data access
        await migrator.migrate(database, restrictSchema);
        final restrictDataAccess = await DataAccess.create(database: database, schema: restrictSchema);

        // Insert test data
        final parentId = await restrictDataAccess.insert('parents', {'name': 'Parent'});
        await restrictDataAccess.insert('children', {'name': 'Child', 'parent_id': parentId});

        // Attempt to delete parent should fail
        expect(
          () => restrictDataAccess.deleteWithChildren('parents', parentId),
          throwsA(isA<StateError>()),
        );

        // But with force=true should succeed
        final deletedCount = await restrictDataAccess.deleteWithChildren('parents', parentId, force: true);
        expect(deletedCount, equals(2)); // Parent and child
      });

      test('cascade delete works with path navigation', () async {
        // Setup test data
        final userId = await dataAccess.insert('users', {
          'username': 'test_user',
          'email': 'test@example.com',
        });

        final postId = await dataAccess.insert('posts', {
          'title': 'Test Post',
          'content': 'Test content',
          'user_id': userId,
        });

        await dataAccess.insert('comments', {
          'content': 'Test comment',
          'post_id': postId,
          'user_id': userId,
        });

        // Verify data exists through path navigation before deletion
        final commentsViaPath = await dataAccess.getRelatedByPath(['users', 'posts', 'comments'], userId);
        expect(commentsViaPath.length, equals(1));

        // Delete with cascade
        final deletedCount = await dataAccess.deleteWithChildren('users', userId);
        expect(deletedCount, greaterThan(0));

        // Verify path navigation returns empty after cascade delete
        final commentsAfterDelete = await dataAccess.getRelatedByPath(['users', 'posts', 'comments'], userId);
        expect(commentsAfterDelete.length, equals(0));
      });
    });

    group('Schema Validation', () {
      test('validates relationship references exist', () {
        expect(
          () => SchemaBuilder()
              .table('users', (table) => table.autoIncrementPrimaryKey('id'))
              .oneToMany('users', 'nonexistent_table'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('prevents duplicate relationships', () {
        expect(
          () => SchemaBuilder()
              .table('users', (table) => table.autoIncrementPrimaryKey('id'))
              .table('posts', (table) => table.autoIncrementPrimaryKey('id'))
              .oneToMany('users', 'posts')
              .oneToMany('users', 'posts'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}