import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('DataAccess Integration Tests', () {
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
      
      // Create a comprehensive test schema
      schema = SchemaBuilder()
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
          .table('tags', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull().unique())
              .text('color', (col) => col.withDefaultValue('#000000')));
      
      // Apply schema to database
      await migrator.migrate(database, schema);
      
      // Create data access instance
      dataAccess = DataAccess(database: database, schema: schema);
    });

    tearDown(() async {
      await database.close();
    });

    group('Primary Key Operations', () {
      test('can insert and retrieve by primary key', () async {
        // Insert a user
        final userId = await dataAccess.insert('users', {
          'username': 'alice',
          'email': 'alice@example.com',
          'full_name': 'Alice Smith',
          'age': 30,
          'balance': 150.75,
        });

        expect(userId, greaterThan(0));

        // Retrieve by primary key
        final user = await dataAccess.getByPrimaryKey('users', userId);
        expect(user, isNotNull);
        expect(user!['username'], equals('alice'));
        expect(user['email'], equals('alice@example.com'));
        expect(user['full_name'], equals('Alice Smith'));
        expect(user['age'], equals(30));
        expect(user['balance'], equals(150.75));
      });

      test('returns null for non-existent primary key', () async {
        final user = await dataAccess.getByPrimaryKey('users', 999);
        expect(user, isNull);
      });

      test('can update by primary key', () async {
        // Insert a user
        final userId = await dataAccess.insert('users', {
          'username': 'bob',
          'email': 'bob@example.com',
          'age': 25,
        });

        // Update specific columns
        final updatedRows = await dataAccess.updateByPrimaryKey('users', userId, {
          'full_name': 'Bob Johnson',
          'age': 26,
          'balance': 200.0,
        });

        expect(updatedRows, equals(1));

        // Verify update
        final user = await dataAccess.getByPrimaryKey('users', userId);
        expect(user!['username'], equals('bob')); // Unchanged
        expect(user['email'], equals('bob@example.com')); // Unchanged
        expect(user['full_name'], equals('Bob Johnson')); // Updated
        expect(user['age'], equals(26)); // Updated
        expect(user['balance'], equals(200.0)); // Updated
      });

      test('can delete by primary key', () async {
        // Insert a user
        final userId = await dataAccess.insert('users', {
          'username': 'charlie',
          'email': 'charlie@example.com',
        });

        // Verify user exists
        expect(await dataAccess.existsByPrimaryKey('users', userId), isTrue);

        // Delete the user
        final deletedRows = await dataAccess.deleteByPrimaryKey('users', userId);
        expect(deletedRows, equals(1));

        // Verify user no longer exists
        expect(await dataAccess.existsByPrimaryKey('users', userId), isFalse);
        expect(await dataAccess.getByPrimaryKey('users', userId), isNull);
      });

      test('can check existence by primary key', () async {
        final userId = await dataAccess.insert('users', {
          'username': 'diana',
          'email': 'diana@example.com',
        });

        expect(await dataAccess.existsByPrimaryKey('users', userId), isTrue);
        expect(await dataAccess.existsByPrimaryKey('users', 999), isFalse);
      });
    });

    group('Query Operations', () {
      setUp(() async {
        // Insert test data
        await dataAccess.insert('users', {
          'username': 'alice',
          'email': 'alice@example.com',
          'age': 30,
          'balance': 100.0,
        });
        await dataAccess.insert('users', {
          'username': 'bob',
          'email': 'bob@example.com',
          'age': 25,
          'balance': 200.0,
        });
        await dataAccess.insert('users', {
          'username': 'charlie',
          'email': 'charlie@example.com',
          'age': 35,
          'balance': 50.0,
        });
      });

      test('can get all rows', () async {
        final users = await dataAccess.getAll('users', orderBy: 'username');
        expect(users, hasLength(3));
        expect(users[0]['username'], equals('alice'));
        expect(users[1]['username'], equals('bob'));
        expect(users[2]['username'], equals('charlie'));
      });

      test('can get rows with where conditions', () async {
        // Get users older than 30
        final users = await dataAccess.getAllWhere('users',
            where: 'age > ?', whereArgs: [30], orderBy: 'age');

        expect(users, hasLength(1));
        expect(users.first['username'], equals('charlie'));
        expect(users.first['age'], equals(35));
      });

      test('can get rows with complex where conditions', () async {
        // Get users with balance between 75 and 175
        final users = await dataAccess.getAllWhere('users',
            where: 'balance BETWEEN ? AND ?',
            whereArgs: [75.0, 175.0],
            orderBy: 'balance DESC');

        expect(users, hasLength(1));
        expect(users.first['username'], equals('alice'));
        expect(users.first['balance'], equals(100.0));
      });

      test('can get rows with limit and offset', () async {
        final users = await dataAccess.getAll('users',
            orderBy: 'username', limit: 2, offset: 1);

        expect(users, hasLength(2));
        expect(users[0]['username'], equals('bob'));
        expect(users[1]['username'], equals('charlie'));
      });

      test('can count rows', () async {
        expect(await dataAccess.count('users'), equals(3));
        expect(await dataAccess.count('users', where: 'age < ?', whereArgs: [30]), equals(1));
        expect(await dataAccess.count('posts'), equals(0));
      });
    });

    group('Bulk Operations', () {
      test('can update multiple rows with where condition', () async {
        // Insert test data
        await dataAccess.insert('users', {'username': 'alice', 'email': 'alice@example.com', 'age': 30});
        await dataAccess.insert('users', {'username': 'bob', 'email': 'bob@example.com', 'age': 25});
        await dataAccess.insert('users', {'username': 'charlie', 'email': 'charlie@example.com', 'age': 35});

        // Update all users with age < 30 to have balance = 50.0
        final updatedRows = await dataAccess.updateWhere('users',
            {'balance': 50.0},
            where: 'age < ?',
            whereArgs: [30]);

        expect(updatedRows, equals(1)); // Only Bob (age 25)

        // Verify the update
        final bob = await dataAccess.getAllWhere('users',
            where: 'username = ?', whereArgs: ['bob']);
        expect(bob.first['balance'], equals(50.0));

        // Verify other users unchanged
        final alice = await dataAccess.getAllWhere('users',
            where: 'username = ?', whereArgs: ['alice']);
        expect(alice.first['balance'], equals(0.0)); // Default value
      });

      test('can delete multiple rows with where condition', () async {
        // Insert test data
        await dataAccess.insert('users', {'username': 'alice', 'email': 'alice@example.com', 'age': 30});
        await dataAccess.insert('users', {'username': 'bob', 'email': 'bob@example.com', 'age': 25});
        await dataAccess.insert('users', {'username': 'charlie', 'email': 'charlie@example.com', 'age': 35});

        // Delete users with age >= 30
        final deletedRows = await dataAccess.deleteWhere('users',
            where: 'age >= ?', whereArgs: [30]);

        expect(deletedRows, equals(2)); // Alice and Charlie

        // Verify only Bob remains
        final remainingUsers = await dataAccess.getAll('users');
        expect(remainingUsers, hasLength(1));
        expect(remainingUsers.first['username'], equals('bob'));
      });
    });

    group('Validation and Error Handling', () {
      test('throws error for non-existent table', () async {
        expect(() => dataAccess.getByPrimaryKey('nonexistent', 1),
            throwsA(isA<ArgumentError>()));
        expect(() => dataAccess.insert('nonexistent', {'col': 'value'}),
            throwsA(isA<ArgumentError>()));
      });

      test('throws error for table without primary key', () async {
        // Create a table without primary key for testing
        await database.execute('CREATE TABLE no_pk (name TEXT)');
        
        expect(() => dataAccess.getByPrimaryKey('no_pk', 1),
            throwsA(isA<ArgumentError>()));
      });

      test('validates required columns on insert', () async {
        // Try to insert user without required username
        expect(() => dataAccess.insert('users', {
              'email': 'test@example.com',
              // Missing required username
            }),
            throwsA(isA<ArgumentError>()));

        // Try to insert user without required email
        expect(() => dataAccess.insert('users', {
              'username': 'test',
              // Missing required email
            }),
            throwsA(isA<ArgumentError>()));
      });

      test('validates column existence on insert and update', () async {
        // Insert with non-existent column
        expect(() => dataAccess.insert('users', {
              'username': 'test',
              'email': 'test@example.com',
              'nonexistent_column': 'value',
            }),
            throwsA(isA<ArgumentError>()));

        // Update with non-existent column
        final userId = await dataAccess.insert('users', {
          'username': 'test',
          'email': 'test@example.com',
        });

        expect(() => dataAccess.updateByPrimaryKey('users', userId, {
              'nonexistent_column': 'value',
            }),
            throwsA(isA<ArgumentError>()));
      });

      test('requires at least one column for update', () async {
        final userId = await dataAccess.insert('users', {
          'username': 'test',
          'email': 'test@example.com',
        });

        expect(() => dataAccess.updateByPrimaryKey('users', userId, {}),
            throwsA(isA<ArgumentError>()));
      });
    });

    group('Table Metadata', () {
      test('can get table metadata', () async {
        final metadata = dataAccess.getTableMetadata('users');

        expect(metadata.tableName, equals('users'));
        expect(metadata.primaryKeyColumn, equals('id'));
        expect(metadata.columns, hasLength(8)); // Now includes systemId and systemVersion
        expect(metadata.requiredColumns, containsAll(['username', 'email'])); // systemId/systemVersion are auto-populated
        expect(metadata.uniqueColumns, containsAll(['username', 'systemId'])); // systemId is unique
        expect(metadata.indices, containsAll(['idx_username', 'idx_email']));

        // Test helper methods
        expect(metadata.isColumnRequired('username'), isTrue);
        expect(metadata.isColumnRequired('full_name'), isFalse);
        expect(metadata.isColumnRequired('systemId'), isFalse); // Auto-populated, not user-required
        expect(metadata.isColumnUnique('username'), isTrue);
        expect(metadata.isColumnUnique('systemId'), isTrue);
        expect(metadata.isColumnUnique('email'), isFalse);
        expect(metadata.isColumnPrimaryKey('id'), isTrue);
        expect(metadata.isColumnPrimaryKey('username'), isFalse);

        // Test data type access
        expect(metadata.getColumnType('id'), equals(SqliteDataType.integer));
        expect(metadata.getColumnType('username'), equals(SqliteDataType.text));
        expect(metadata.getColumnType('age'), equals(SqliteDataType.integer));
        expect(metadata.getColumnType('balance'), equals(SqliteDataType.real));
        expect(metadata.getColumnType('systemId'), equals(SqliteDataType.text));
        expect(metadata.getColumnType('systemVersion'), equals(SqliteDataType.text));
      });

      test('can get metadata for different tables', () async {
        final postsMetadata = dataAccess.getTableMetadata('posts');

        expect(postsMetadata.tableName, equals('posts'));
        expect(postsMetadata.primaryKeyColumn, equals('id'));
        expect(postsMetadata.requiredColumns, containsAll(['title', 'user_id'])); // systemId/systemVersion excluded
        expect(postsMetadata.uniqueColumns, contains('systemId')); // Only systemId is unique
        expect(postsMetadata.indices, containsAll(['idx_user_id', 'idx_title_user']));
      });
    });

    group('Complex Scenarios', () {
      test('can work with related data across tables', () async {
        // Insert a user
        final userId = await dataAccess.insert('users', {
          'username': 'author',
          'email': 'author@example.com',
          'full_name': 'Article Author',
        });

        // Insert posts for the user
        final post1Id = await dataAccess.insert('posts', {
          'title': 'First Post',
          'content': 'This is my first post.',
          'user_id': userId,
          'likes': 5,
        });

        final post2Id = await dataAccess.insert('posts', {
          'title': 'Second Post',
          'content': 'This is my second post.',
          'user_id': userId,
          'likes': 12,
        });

        // Query posts by user
        final userPosts = await dataAccess.getAllWhere('posts',
            where: 'user_id = ?',
            whereArgs: [userId],
            orderBy: 'likes DESC');

        expect(userPosts, hasLength(2));
        expect(userPosts[0]['title'], equals('Second Post'));
        expect(userPosts[0]['likes'], equals(12));
        expect(userPosts[1]['title'], equals('First Post'));
        expect(userPosts[1]['likes'], equals(5));

        // Update post likes
        await dataAccess.updateByPrimaryKey('posts', post1Id, {'likes': 20});

        // Verify the update
        final updatedPost = await dataAccess.getByPrimaryKey('posts', post1Id);
        expect(updatedPost!['likes'], equals(20));

        // Get most liked posts across all users
        final popularPosts = await dataAccess.getAllWhere('posts',
            where: 'likes > ?',
            whereArgs: [10],
            orderBy: 'likes DESC');

        expect(popularPosts, hasLength(2));
        expect(popularPosts[0]['likes'], equals(20));
        expect(popularPosts[1]['likes'], equals(12));
      });

      test('handles default values correctly', () async {
        // Insert user with minimal required fields
        final userId = await dataAccess.insert('users', {
          'username': 'minimal',
          'email': 'minimal@example.com',
        });

        // Retrieve and verify defaults were applied
        final user = await dataAccess.getByPrimaryKey('users', userId);
        expect(user!['age'], equals(0)); // Default value
        expect(user['balance'], equals(0.0)); // Default value
        expect(user['full_name'], isNull); // No default, nullable

        // Insert tag with partial defaults
        final tagId = await dataAccess.insert('tags', {
          'name': 'flutter',
          // color will use default
        });

        final tag = await dataAccess.getByPrimaryKey('tags', tagId);
        expect(tag!['name'], equals('flutter'));
        expect(tag['color'], equals('#000000')); // Default value
      });
    });
  });

  group('Bulk Loading Operations', () {
    late Database database;
    late SchemaBuilder schema;
    late DataAccess dataAccess;

    setUpAll(() {
      // Initialize sqflite_ffi for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      database = await openDatabase(inMemoryDatabasePath);
      
      // Create schema for bulk loading tests
      schema = SchemaBuilder()
        .table('products', (table) => table
            .autoIncrementPrimaryKey('id')
            .text('name', (col) => col.notNull())
            .text('description')
            .real('price', (col) => col.notNull())
            .integer('stock', (col) => col.withDefaultValue(0))
            .text('category', (col) => col.notNull())
            .index('idx_category', ['category'])
            .index('idx_name', ['name']))
        .table('users', (table) => table
            .autoIncrementPrimaryKey('id')
            .text('email', (col) => col.unique().notNull())
            .text('name', (col) => col.notNull())
            .integer('age')
            .text('city'));

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
      
      dataAccess = DataAccess(database: database, schema: schema);
    });

    tearDown(() async {
      await database.close();
    });

    test('can bulk load dataset with matching columns', () async {
      final dataset = [
        {
          'name': 'Laptop',
          'description': 'Gaming laptop',
          'price': 999.99,
          'stock': 10,
          'category': 'Electronics'
        },
        {
          'name': 'Mouse',
          'description': 'Wireless mouse',
          'price': 29.99,
          'stock': 50,
          'category': 'Electronics'
        },
        {
          'name': 'Desk',
          'description': 'Standing desk',
          'price': 199.99,
          'stock': 5,
          'category': 'Furniture'
        },
      ];

      final result = await dataAccess.bulkLoad('products', dataset);
      
      expect(result.rowsProcessed, equals(3));
      expect(result.rowsInserted, equals(3));
      expect(result.rowsSkipped, equals(0));
      expect(result.isComplete, isTrue);
      expect(result.hasInsertions, isTrue);
      
      // Verify data was inserted correctly
      final products = await dataAccess.getAll('products');
      expect(products, hasLength(3));
      expect(products.first['name'], equals('Laptop'));
      expect(products.last['name'], equals('Desk'));
    });

    test('can handle dataset with extra columns', () async {
      final dataset = [
        {
          'name': 'Book',
          'description': 'Programming book',
          'price': 39.99,
          'category': 'Books',
          'isbn': '978-0123456789', // Extra column not in table
          'pages': 500, // Extra column not in table
          'author': 'John Doe', // Extra column not in table
        },
        {
          'name': 'Pen',
          'price': 4.99,
          'category': 'Stationery',
          'color': 'Blue', // Extra column not in table
        },
      ];

      final result = await dataAccess.bulkLoad('products', dataset);
      
      expect(result.rowsProcessed, equals(2));
      expect(result.rowsInserted, equals(2));
      expect(result.rowsSkipped, equals(0));
      expect(result.isComplete, isTrue);
      
      // Verify data was inserted correctly (extra columns ignored)
      final products = await dataAccess.getAll('products');
      expect(products, hasLength(2));
      expect(products.first['name'], equals('Book'));
      expect(products.first['price'], equals(39.99));
      expect(products.first['stock'], equals(0)); // Default value
      expect(products.first.containsKey('isbn'), isFalse); // Extra column ignored
    });

    test('can handle dataset with missing optional columns', () async {
      final dataset = [
        {
          'name': 'Chair',
          'price': 89.99,
          'category': 'Furniture',
          // missing description and stock (optional columns)
        },
        {
          'name': 'Table',
          'price': 149.99,
          'category': 'Furniture',
          'description': 'Wooden table',
          // missing stock (optional with default)
        },
      ];

      final result = await dataAccess.bulkLoad('products', dataset);
      
      expect(result.rowsProcessed, equals(2));
      expect(result.rowsInserted, equals(2));
      expect(result.rowsSkipped, equals(0));
      
      final products = await dataAccess.getAll('products');
      expect(products, hasLength(2));
      expect(products.first['description'], isNull);
      expect(products.first['stock'], equals(0)); // Default value
      expect(products.last['stock'], equals(0)); // Default value
    });

    test('throws error for missing required columns by default', () async {
      final dataset = [
        {
          'name': 'Incomplete Product',
          'price': 9.99,
          // missing required 'category' column
        },
      ];

      expect(
        () => dataAccess.bulkLoad('products', dataset),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Required columns are missing')
        ))
      );
    });

    test('can skip rows with missing required columns when allowed', () async {
      final dataset = [
        {
          'name': 'Valid Product',
          'price': 19.99,
          'category': 'Valid'
        },
        {
          'name': 'Invalid Product',
          'price': 9.99,
          // missing required 'category' column
        },
        {
          'name': 'Another Valid Product',
          'price': 29.99,
          'category': 'Valid'
        },
      ];

      final result = await dataAccess.bulkLoad(
        'products',
        dataset,
        options: const BulkLoadOptions(
          allowPartialData: true,
          collectErrors: true,
        ),
      );
      
      expect(result.rowsProcessed, equals(3));
      expect(result.rowsInserted, equals(2));
      expect(result.rowsSkipped, equals(1));
      expect(result.isComplete, isFalse);
      expect(result.hasInsertions, isTrue);
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Missing required columns'));
      
      final products = await dataAccess.getAll('products');
      expect(products, hasLength(2));
      expect(products.every((p) => p['category'] == 'Valid'), isTrue);
    });

    test('can use custom batch size', () async {
      final dataset = List.generate(10, (i) => {
        'name': 'Product $i',
        'price': (i + 1) * 10.0,
        'category': 'Test',
      });

      final result = await dataAccess.bulkLoad(
        'products',
        dataset,
        options: const BulkLoadOptions(batchSize: 3),
      );
      
      expect(result.rowsProcessed, equals(10));
      expect(result.rowsInserted, equals(10));
      expect(result.rowsSkipped, equals(0));
      
      final products = await dataAccess.getAll('products');
      expect(products, hasLength(10));
    });

    test('returns empty result for empty dataset', () async {
      final result = await dataAccess.bulkLoad('products', []);
      
      expect(result.rowsProcessed, equals(0));
      expect(result.rowsInserted, equals(0));
      expect(result.rowsSkipped, equals(0));
      expect(result.isComplete, isTrue);
      expect(result.hasInsertions, isFalse);
    });

    test('works with large datasets efficiently', () async {
      // Generate a moderately large dataset
      final dataset = List.generate(5000, (i) => {
        'name': 'Product $i',
        'description': 'Description for product $i',
        'price': (i % 100 + 1) * 1.99,
        'stock': i % 50,
        'category': 'Category ${i % 10}',
      });

      final stopwatch = Stopwatch()..start();
      final result = await dataAccess.bulkLoad('products', dataset);
      stopwatch.stop();
      
      expect(result.rowsProcessed, equals(5000));
      expect(result.rowsInserted, equals(5000));
      expect(result.rowsSkipped, equals(0));
      expect(result.isComplete, isTrue);
      
      // Verify performance (should complete reasonably quickly)
      expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Less than 5 seconds
      
      // Spot check some data
      final count = await dataAccess.count('products');
      expect(count, equals(5000));
      
      final product = await dataAccess.getByPrimaryKey('products', 1);
      expect(product!['name'], equals('Product 0'));
    });

    test('validates data when validation is enabled', () async {
      final dataset = [
        {
          'name': 'Valid Product',
          'price': 19.99,
          'category': 'Valid',
        },
      ];

      // First test that validation works for invalid column existence
      final invalidDataset = [
        {
          'name': 'Product',
          'price': 19.99, 
          'category': 'Valid',
          'description': null, // Valid column with null value - should work
        },
      ];

      // This should work - null is allowed for optional columns
      final result = await dataAccess.bulkLoad(
        'products',
        invalidDataset,
        options: const BulkLoadOptions(validateData: true),
      );
      
      expect(result.rowsProcessed, equals(1));
      expect(result.rowsInserted, equals(1));
      expect(result.rowsSkipped, equals(0));
      
      // Test validation with missing required columns causes error
      final missingRequiredDataset = [
        {
          'name': 'Product',
          'price': 19.99,
          // missing required 'category'
        },
      ];

      expect(
        () => dataAccess.bulkLoad(
          'products',
          missingRequiredDataset,
          options: const BulkLoadOptions(validateData: true),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Required columns are missing from dataset')
        ))
      );
    });

    test('skips validation when disabled', () async {
      final dataset = [
        {
          'name': 'Product',
          'price': 19.99,
          'category': 'Valid',
        },
      ];

      final result = await dataAccess.bulkLoad(
        'products',
        dataset,
        options: const BulkLoadOptions(validateData: false),
      );
      
      expect(result.rowsProcessed, equals(1));
      expect(result.rowsInserted, equals(1));
      expect(result.rowsSkipped, equals(0));
    });
  });
}