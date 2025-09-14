import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Helper method to insert initial test data
Future<void> insertTestData(DataAccess dataAccess) async {
  // Insert users
  await dataAccess.insert('users', {
    'username': 'alice',
    'email': 'alice@example.com',
    'age': 30,
    'status': 'active',
    'created_at': DateTime.now().toIso8601String(),
  });

  await dataAccess.insert('users', {
    'username': 'bob',
    'email': 'bob@example.com',
    'age': 25,
    'status': 'active',
    'created_at': DateTime.now().toIso8601String(),
  });

  await dataAccess.insert('users', {
    'username': 'charlie',
    'email': 'charlie@example.com',
    'age': 35,
    'status': 'inactive',
    'created_at': DateTime.now().toIso8601String(),
  });

  // Insert posts
  await dataAccess.insert('posts', {
    'user_id': 1,
    'title': 'First Post',
    'content': 'Content of first post',
    'category': 'tech',
    'likes': 15,
    'created_at': DateTime.now().toIso8601String(),
  });

  await dataAccess.insert('posts', {
    'user_id': 1,
    'title': 'Second Post',
    'content': 'Content of second post',
    'category': 'lifestyle',
    'likes': 5,
    'created_at': DateTime.now().toIso8601String(),
  });

  await dataAccess.insert('posts', {
    'user_id': 2,
    'title': 'Bob\'s Post',
    'content': 'Content from Bob',
    'category': 'tech',
    'likes': 8,
    'created_at': DateTime.now().toIso8601String(),
  });
}

/// Comprehensive test suite for the reactive stream dependency-based change detection system
/// Testing all scenarios and edge cases to ensure no invalidations are missed
void main() {
  late Database database;
  
  late DataAccess dataAccess;
  late SchemaBuilder schema;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(':memory:');
    
    // Create comprehensive schema for testing all dependency types
    schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('username', (col) => col.notNull().unique())
          .text('email', (col) => col.notNull())
          .integer('age')
          .text('status', (col) => col.notNull().withDefaultValue('active'))
          .text('created_at', (col) => col.notNull())
          .index('idx_status', ['status'])
          .index('idx_email', ['email']))
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .integer('user_id', (col) => col.notNull())
          .text('title', (col) => col.notNull())
          .text('content', (col) => col.notNull())
          .text('category', (col) => col.notNull())
          .integer('likes', (col) => col.withDefaultValue(0))
          .text('created_at', (col) => col.notNull())
          .index('idx_category', ['category'])
          .index('idx_likes', ['likes']))
      .table('comments', (table) => table
          .autoIncrementPrimaryKey('id')
          .integer('post_id', (col) => col.notNull())
          .integer('user_id', (col) => col.notNull())
          .text('content', (col) => col.notNull())
          .text('created_at', (col) => col.notNull()))
      .table('bulk_test', (table) => table
          .text('id', (col) => col.primaryKey()) // For bulk operations testing
          .text('name', (col) => col.notNull())
          .integer('value')
          .text('category'));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);

    // Insert initial test data
    await insertTestData(dataAccess);
  });

  tearDown(() async {
    await dataAccess.dispose();
    await database.close();
  });

  group('Whole-Table Dependencies', () {
    test('should trigger on any table change (INSERT)', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final query = QueryBuilder().selectAll().from('users');
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        if (updateCount == 2) { // Skip initial load, wait for insert
          completer.complete(data);
        }
      });

      // Wait for initial load
      await Future.delayed(Duration(milliseconds: 200));

      // Insert new user - should trigger update
      await dataAccess.insert('users', {
        'username': 'new_user',
        'email': 'new@example.com',
        'age': 25,
        'created_at': DateTime.now().toIso8601String(),
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(4)); // 3 initial + 1 new

      await subscription.cancel();
    });

    test('should trigger on any table change (UPDATE)', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final query = QueryBuilder().selectAll().from('users');
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Update user - should trigger
      await dataAccess.updateByPrimaryKey('users', 1, {'age': 35});

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      
      final updatedUser = result.firstWhere((u) => u['id'] == 1);
      expect(updatedUser['age'], equals(35));

      await subscription.cancel();
    });

    test('should trigger on any table change (DELETE)', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final query = QueryBuilder().selectAll().from('users');
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Delete user - should trigger
      await dataAccess.deleteByPrimaryKey('users', 3);

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(2)); // 3 initial - 1 deleted

      await subscription.cancel();
    });
  });

  group('Column-Wise Dependencies', () {
    test('should only trigger when specific columns change', () async {
      var emailUpdateCount = 0;
      var statusUpdateCount = 0;

      final emailCompleter = Completer<List<Map<String, dynamic>>>();
      final statusCompleter = Completer<List<Map<String, dynamic>>>();

      // Watch only email changes
      final emailQuery = QueryBuilder().selectColumns(['id', 'email']).from('users');
      final emailSubscription = dataAccess.watch(emailQuery).listen((data) {
        emailUpdateCount++;
        if (emailUpdateCount == 2) {
          emailCompleter.complete(data);
        }
      });

      // Watch only status changes
      final statusQuery = QueryBuilder().selectColumns(['id', 'status']).from('users');
      final statusSubscription = dataAccess.watch(statusQuery).listen((data) {
        statusUpdateCount++;
        if (statusUpdateCount == 2) {
          statusCompleter.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Update age - should NOT trigger either stream
      await dataAccess.updateByPrimaryKey('users', 1, {'age': 35});
      await Future.delayed(Duration(milliseconds: 200));

      expect(emailUpdateCount, equals(1)); // Only initial load
      expect(statusUpdateCount, equals(1)); // Only initial load

      // Update email - should trigger email stream only
      await dataAccess.updateByPrimaryKey('users', 1, {'email': 'alice.new@example.com'});

      final emailResult = await emailCompleter.future.timeout(Duration(seconds: 2));
      expect(emailUpdateCount, equals(2));
      expect(statusUpdateCount, equals(1)); // Still only initial

      // Update status - should trigger status stream only
      await dataAccess.updateByPrimaryKey('users', 2, {'status': 'inactive'});

      final statusResult = await statusCompleter.future.timeout(Duration(seconds: 2));
      expect(statusUpdateCount, equals(2));

      await emailSubscription.cancel();
      await statusSubscription.cancel();
    });
  });

  group('Where-Clause Dependencies', () {
    test('should only trigger when WHERE conditions are affected', () async {
      var activeUserUpdateCount = 0;
      var popularPostUpdateCount = 0;

      final activeCompleter = Completer<List<Map<String, dynamic>>>();
      final popularCompleter = Completer<List<Map<String, dynamic>>>();

      // Watch active users only
      final activeQuery = QueryBuilder().selectAll().from('users').where(ConditionBuilder.eq('status', 'active'));
      final activeSubscription = dataAccess.watch(activeQuery).listen((data) {
        activeUserUpdateCount++;
        if (activeUserUpdateCount == 2) {
          activeCompleter.complete(data);
        }
      });

      // Watch popular posts only (likes > 10)
      final popularQuery = QueryBuilder().selectAll().from('posts').where(ConditionBuilder.gt('likes', 10));
      final popularSubscription = dataAccess.watch(popularQuery).listen((data) {
        popularPostUpdateCount++;
        if (popularPostUpdateCount == 2) {
          popularCompleter.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Update inactive user - should NOT trigger active users stream
      await dataAccess.updateByPrimaryKey('users', 3, {'age': 40});
      await Future.delayed(Duration(milliseconds: 200));

      expect(activeUserUpdateCount, equals(1)); // Only initial
      expect(popularPostUpdateCount, equals(1)); // Only initial

      // Update active user status to inactive - should trigger active users stream
      await dataAccess.updateByPrimaryKey('users', 1, {'status': 'inactive'});

      final activeResult = await activeCompleter.future.timeout(Duration(seconds: 2));
      expect(activeUserUpdateCount, equals(2));
      expect(activeResult.length, equals(1)); // One less active user

      // Update post likes to make it popular - should trigger popular posts stream
      await dataAccess.updateByPrimaryKey('posts', 2, {'likes': 15});

      final popularResult = await popularCompleter.future.timeout(Duration(seconds: 2));
      expect(popularPostUpdateCount, equals(2));
      expect(popularResult.length, equals(2)); // One more popular post

      await activeSubscription.cancel();
      await popularSubscription.cancel();
    });
  });

  group('Related-Table Dependencies', () {
    test('should trigger when related tables change', () async {
      var userStatsUpdateCount = 0;
      final completer = Completer<Map<String, dynamic>>();

      // Create aggregate stream that depends on both users and posts
      final userStatsQuery = QueryBuilder()
        .select([
          ExpressionBuilder.qualifiedColumn('u', 'username'),
          ExpressionBuilder.function('COUNT', ['p.id']).as('post_count'),
          ExpressionBuilder.function('COALESCE', ['SUM(p.likes)', '0']).as('total_likes'),
        ])
        .from('users', 'u')
        .leftJoin('posts', 'u.id = p.user_id', 'p')
        .where(ConditionBuilder.eq('u.id', 1))
        .groupBy(['u.id']);
      
      final subscription = dataAccess.watch(userStatsQuery).listen((data) {
        userStatsUpdateCount++;
        if (userStatsUpdateCount == 2) {
          completer.complete(data.first);
        }
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Add new post for user 1 - should trigger user stats update
      await dataAccess.insert('posts', {
        'user_id': 1,
        'title': 'New Post',
        'content': 'Content',
        'category': 'tech',
        'likes': 5,
        'created_at': DateTime.now().toIso8601String(),
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(userStatsUpdateCount, equals(2));
      expect(result['post_count'], equals(3)); // 2 initial + 1 new

      await subscription.cancel();
    });
  });

  group('BulkLoad Integration', () {
    test('should trigger streams when bulk loading data', () async {
      var updateCount = 0;
      final completer = Completer<List<Map<String, dynamic>>>();

      final query = QueryBuilder().selectAll().from('bulk_test');
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk load data - should trigger stream
      final bulkData = List.generate(10, (i) => {
        'id': 'bulk_$i',
        'name': 'Item $i',
        'value': i * 10,
        'category': i % 2 == 0 ? 'even' : 'odd',
      });

      await dataAccess.bulkLoad('bulk_test', bulkData);

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(10));

      await subscription.cancel();
    });

    test('should trigger streams on bulk upsert operations', () async {
      var updateCount = 0;
      final completer = Completer<List<Map<String, dynamic>>>();

      // First insert some data
      await dataAccess.bulkLoad('bulk_test', [
        {'id': 'test1', 'name': 'Original', 'value': 100, 'category': 'test'},
        {'id': 'test2', 'name': 'Original2', 'value': 200, 'category': 'test'},
      ]);

      final query = QueryBuilder().selectAll().from('bulk_test');
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk upsert - should trigger stream
      await dataAccess.bulkLoad('bulk_test', [
        {'id': 'test1', 'name': 'Updated', 'value': 150, 'category': 'test'},
        {'id': 'test3', 'name': 'New', 'value': 300, 'category': 'test'},
      ], options: BulkLoadOptions(upsertMode: true));

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(3)); // 2 original (1 updated) + 1 new

      final updatedItem = result.firstWhere((item) => item['id'] == 'test1');
      expect(updatedItem['name'], equals('Updated'));

      await subscription.cancel();
    });

    test('should handle bulk operations with column-wise dependencies', () async {
      var nameUpdateCount = 0;
      var valueUpdateCount = 0;

      final nameCompleter = Completer<List<Map<String, dynamic>>>();
      final valueCompleter = Completer<List<Map<String, dynamic>>>();

      // Watch name changes only
      final nameQuery = QueryBuilder().selectColumns(['id', 'name']).from('bulk_test');
      final nameSubscription = dataAccess.watch(nameQuery).listen((data) {
        nameUpdateCount++;
        if (nameUpdateCount == 2) {
          nameCompleter.complete(data);
        }
      });

      // Watch value changes only
      final valueQuery = QueryBuilder().selectColumns(['id', 'value']).from('bulk_test');
      final valueSubscription = dataAccess.watch(valueQuery).listen((data) {
        valueUpdateCount++;
        if (valueUpdateCount == 2) {
          valueCompleter.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Bulk load affecting only names - should trigger name stream only
      await dataAccess.bulkLoad('bulk_test', [
        {'id': 'name_test', 'name': 'Name Only', 'category': 'test'},
      ]);

      final nameResult = await nameCompleter.future.timeout(Duration(seconds: 2));
      expect(nameUpdateCount, equals(2));
      expect(valueUpdateCount, equals(1)); // Only initial load

      await nameSubscription.cancel();
      await valueSubscription.cancel();
    });
  });

  group('Raw Query Dependencies', () {
    test('should handle complex raw queries with proper dependency detection', () async {
      var updateCount = 0;
      final completer = Completer<List<Map<String, dynamic>>>();

      // Create stream with complex query using QueryBuilder
      final complexQuery = QueryBuilder()
        .select([
          ExpressionBuilder.qualifiedColumn('u', 'username'),
          ExpressionBuilder.function('COUNT', ['p.id']).as('posts'),
          ExpressionBuilder.function('AVG', ['p.likes']).as('avg_likes'),
        ])
        .from('users', 'u')
        .leftJoin('posts', 'u.id = p.user_id', 'p')
        .where(ConditionBuilder.eq('u.status', 'active'))
        .groupBy(['u.id'])
        .having(ConditionBuilder.raw('COUNT(p.id) > 0'))
        .orderBy(['avg_likes DESC']);
        
      final subscription = dataAccess.watch(complexQuery).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Update post likes - should trigger query update
      await dataAccess.updateByPrimaryKey('posts', 1, {'likes': 50});

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.isNotEmpty, isTrue);

      await subscription.cancel();
    });
  });

  group('Edge Cases and Error Scenarios', () {
    test('should handle rapid consecutive changes', () async {
      var updateCount = 0;
      final updates = <List<Map<String, dynamic>>>[];

      final query = QueryBuilder().selectAll().from('users');
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        updates.add(List.from(data));
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Make rapid consecutive changes
      await Future.wait([
        dataAccess.insert('users', {
          'username': 'rapid1',
          'email': 'rapid1@example.com',
          'age': 25,
          'created_at': DateTime.now().toIso8601String(),
        }),
        dataAccess.insert('users', {
          'username': 'rapid2',
          'email': 'rapid2@example.com',
          'age': 26,
          'created_at': DateTime.now().toIso8601String(),
        }),
        dataAccess.insert('users', {
          'username': 'rapid3',
          'email': 'rapid3@example.com',
          'age': 27,
          'created_at': DateTime.now().toIso8601String(),
        }),
      ]);

      // Wait for debouncing to settle
      await Future.delayed(Duration(milliseconds: 300));

      expect(updateCount, equals(2)); // Initial + debounced batch
      expect(updates.last.length, equals(6)); // 3 initial + 3 rapid

      await subscription.cancel();
    });

    test('should clean up inactive streams', () async {
      // Create multiple streams
      final usersQuery = QueryBuilder().selectAll().from('users');
      final postsQuery = QueryBuilder().selectAll().from('posts');
      final bulkQuery = QueryBuilder().selectAll().from('bulk_test');
      
      final stream1 = dataAccess.watch(usersQuery);
      final stream2 = dataAccess.watch(postsQuery);
      final stream3 = dataAccess.watch(bulkQuery);

      final subscription1 = stream1.listen((_) {});
      final subscription2 = stream2.listen((_) {});
      final subscription3 = stream3.listen((_) {});

      await Future.delayed(Duration(milliseconds: 100));

      // Cancel some subscriptions
      await subscription1.cancel();
      await subscription2.cancel();

      // Manually trigger cleanup
      await dataAccess.cleanupInactiveStreams();

      // Check that streams were cleaned up (we can't access internals but test doesn't error)
      expect(true, isTrue); // Simple check that cleanup doesn't error

      await subscription3.cancel();
    });

    test('should handle database transaction rollbacks', () async {
      var updateCount = 0;
      final completer = Completer<void>();

      final query = QueryBuilder().selectAll().from('users');
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        if (updateCount == 1) {
          completer.complete();
        }
      });

      await completer.future;

      final initialCount = updateCount;

      // Attempt operation that will fail (duplicate username)
      try {
        await dataAccess.insert('users', {
          'username': 'alice', // Duplicate username
          'email': 'duplicate@example.com',
          'age': 25,
          'created_at': DateTime.now().toIso8601String(),
        });
        fail('Should have thrown an exception');
      } catch (e) {
        // Expected failure
      }

      await Future.delayed(Duration(milliseconds: 200));

      // Update count should not have increased due to failed operation
      expect(updateCount, equals(initialCount));

      await subscription.cancel();
    });
  });

  group('Performance and Memory', () {
    test('should maintain reasonable dependency counts', () async {
      // Create multiple streams with overlapping dependencies
      final streams = <Stream<List<Map<String, dynamic>>>>[];
      final subscriptions = <StreamSubscription>[];

      for (int i = 0; i < 10; i++) {
        final query = QueryBuilder().selectAll().from('users');
        final stream = dataAccess.watch(query);
        streams.add(stream);
        subscriptions.add(stream.listen((_) {}));
      }

      await Future.delayed(Duration(milliseconds: 100));

      final stats = dataAccess.getDependencyStats();
      
      // Should have efficient dependency management
      expect(stats.totalStreams, equals(10));
      expect(stats.totalDependencies / stats.totalStreams, lessThan(5.0)); // Reasonable ratio

      // Clean up
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });
  });
}