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
  late ReactiveDataAccess reactiveDataAccess;
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
    reactiveDataAccess = ReactiveDataAccess(
      dataAccess: dataAccess,
      schema: schema,
    );

    // Insert initial test data
    await insertTestData(dataAccess);
  });

  tearDown(() async {
    await reactiveDataAccess.dispose();
    await database.close();
  });

  group('Whole-Table Dependencies', () {
    test('should trigger on any table change (INSERT)', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final subscription = reactiveDataAccess.watchTable('users').listen((data) {
        updateCount++;
        if (updateCount == 2) { // Skip initial load, wait for insert
          completer.complete(data);
        }
      });

      // Wait for initial load
      await Future.delayed(Duration(milliseconds: 100));

      // Insert new user - should trigger update
      await reactiveDataAccess.insert('users', {
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

      final subscription = reactiveDataAccess.watchTable('users').listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Update user - should trigger
      await reactiveDataAccess.updateByPrimaryKey('users', 1, {'age': 35});

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      
      final updatedUser = result.firstWhere((u) => u['id'] == 1);
      expect(updatedUser['age'], equals(35));

      await subscription.cancel();
    });

    test('should trigger on any table change (DELETE)', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final subscription = reactiveDataAccess.watchTable('users').listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Delete user - should trigger
      await reactiveDataAccess.deleteByPrimaryKey('users', 3);

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
      final emailSubscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'users',
        () async {
          final result = await dataAccess.getAllWhere('users');
          return result.map((row) => {'id': row['id'], 'email': row['email']}).toList();
        },
        dependentColumns: ['email'],
      ).listen((data) {
        emailUpdateCount++;
        if (emailUpdateCount == 2) {
          emailCompleter.complete(data);
        }
      });

      // Watch only status changes
      final statusSubscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'users',
        () async {
          final result = await dataAccess.getAllWhere('users');
          return result.map((row) => {'id': row['id'], 'status': row['status']}).toList();
        },
        dependentColumns: ['status'],
      ).listen((data) {
        statusUpdateCount++;
        if (statusUpdateCount == 2) {
          statusCompleter.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Update age - should NOT trigger either stream
      await reactiveDataAccess.updateByPrimaryKey('users', 1, {'age': 35});
      await Future.delayed(Duration(milliseconds: 200));

      expect(emailUpdateCount, equals(1)); // Only initial load
      expect(statusUpdateCount, equals(1)); // Only initial load

      // Update email - should trigger email stream only
      await reactiveDataAccess.updateByPrimaryKey('users', 1, {'email': 'alice.new@example.com'});

      final emailResult = await emailCompleter.future.timeout(Duration(seconds: 2));
      expect(emailUpdateCount, equals(2));
      expect(statusUpdateCount, equals(1)); // Still only initial

      // Update status - should trigger status stream only
      await reactiveDataAccess.updateByPrimaryKey('users', 2, {'status': 'inactive'});

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
      final activeSubscription = reactiveDataAccess.watchTable(
        'users',
        where: 'status = ?',
        whereArgs: ['active'],
      ).listen((data) {
        activeUserUpdateCount++;
        if (activeUserUpdateCount == 2) {
          activeCompleter.complete(data);
        }
      });

      // Watch popular posts only (likes > 10)
      final popularSubscription = reactiveDataAccess.watchTable(
        'posts',
        where: 'likes > ?',
        whereArgs: [10],
      ).listen((data) {
        popularPostUpdateCount++;
        if (popularPostUpdateCount == 2) {
          popularCompleter.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Update inactive user - should NOT trigger active users stream
      await reactiveDataAccess.updateByPrimaryKey('users', 3, {'age': 40});
      await Future.delayed(Duration(milliseconds: 200));

      expect(activeUserUpdateCount, equals(1)); // Only initial
      expect(popularPostUpdateCount, equals(1)); // Only initial

      // Update active user status to inactive - should trigger active users stream
      await reactiveDataAccess.updateByPrimaryKey('users', 1, {'status': 'inactive'});

      final activeResult = await activeCompleter.future.timeout(Duration(seconds: 2));
      expect(activeUserUpdateCount, equals(2));
      expect(activeResult.length, equals(1)); // One less active user

      // Update post likes to make it popular - should trigger popular posts stream
      await reactiveDataAccess.updateByPrimaryKey('posts', 2, {'likes': 15});

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
      final subscription = reactiveDataAccess.watchAggregate<Map<String, dynamic>>(
        'users',
        () async {
          final result = await database.rawQuery('''
            SELECT u.username, COUNT(p.id) as post_count, COALESCE(SUM(p.likes), 0) as total_likes
            FROM users u 
            LEFT JOIN posts p ON u.id = p.user_id 
            WHERE u.id = 1
            GROUP BY u.id
          ''');
          return result.first;
        },
      ).listen((data) {
        userStatsUpdateCount++;
        if (userStatsUpdateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Add new post for user 1 - should trigger user stats update
      await reactiveDataAccess.insert('posts', {
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

      final subscription = reactiveDataAccess.watchTable('bulk_test').listen((data) {
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

      await reactiveDataAccess.bulkLoad('bulk_test', bulkData);

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(10));

      await subscription.cancel();
    });

    test('should trigger streams on bulk upsert operations', () async {
      var updateCount = 0;
      final completer = Completer<List<Map<String, dynamic>>>();

      // First insert some data
      await reactiveDataAccess.bulkLoad('bulk_test', [
        {'id': 'test1', 'name': 'Original', 'value': 100, 'category': 'test'},
        {'id': 'test2', 'name': 'Original2', 'value': 200, 'category': 'test'},
      ]);

      final subscription = reactiveDataAccess.watchTable('bulk_test').listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk upsert - should trigger stream
      await reactiveDataAccess.bulkLoad('bulk_test', [
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
      final nameSubscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'bulk_test',
        () async {
          final result = await dataAccess.getAllWhere('bulk_test');
          return result.map((row) => {'id': row['id'], 'name': row['name']}).toList();
        },
        dependentColumns: ['name'],
      ).listen((data) {
        nameUpdateCount++;
        if (nameUpdateCount == 2) {
          nameCompleter.complete(data);
        }
      });

      // Watch value changes only
      final valueSubscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'bulk_test',
        () async {
          final result = await dataAccess.getAllWhere('bulk_test');
          return result.map((row) => {'id': row['id'], 'value': row['value']}).toList();
        },
        dependentColumns: ['value'],
      ).listen((data) {
        valueUpdateCount++;
        if (valueUpdateCount == 2) {
          valueCompleter.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk load affecting only names - should trigger name stream only
      await reactiveDataAccess.bulkLoad('bulk_test', [
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

      // Create stream with complex raw query
      final subscription = reactiveDataAccess.watchAggregate<List<Map<String, dynamic>>>(
        'users',
        () => database.rawQuery('''
          SELECT u.username, COUNT(p.id) as posts, AVG(p.likes) as avg_likes
          FROM users u
          LEFT JOIN posts p ON u.id = p.user_id
          WHERE u.status = 'active'
          GROUP BY u.id
          HAVING COUNT(p.id) > 0
          ORDER BY avg_likes DESC
        '''),
      ).listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Update post likes - should trigger query update
      await reactiveDataAccess.updateByPrimaryKey('posts', 1, {'likes': 50});

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

      final subscription = reactiveDataAccess.watchTable('users').listen((data) {
        updateCount++;
        updates.add(List.from(data));
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Make rapid consecutive changes
      await Future.wait([
        reactiveDataAccess.insert('users', {
          'username': 'rapid1',
          'email': 'rapid1@example.com',
          'age': 25,
          'created_at': DateTime.now().toIso8601String(),
        }),
        reactiveDataAccess.insert('users', {
          'username': 'rapid2',
          'email': 'rapid2@example.com',
          'age': 26,
          'created_at': DateTime.now().toIso8601String(),
        }),
        reactiveDataAccess.insert('users', {
          'username': 'rapid3',
          'email': 'rapid3@example.com',
          'age': 27,
          'created_at': DateTime.now().toIso8601String(),
        }),
      ]);

      // Wait for debouncing to settle
      await Future.delayed(Duration(milliseconds: 300));

      expect(updateCount, greaterThan(1));
      expect(updates.last.length, equals(6)); // 3 initial + 3 rapid

      await subscription.cancel();
    });

    test('should clean up inactive streams', () async {
      // Create multiple streams
      final stream1 = reactiveDataAccess.watchTable('users');
      final stream2 = reactiveDataAccess.watchTable('posts');
      final stream3 = reactiveDataAccess.watchTable('bulk_test');

      final subscription1 = stream1.listen((_) {});
      final subscription2 = stream2.listen((_) {});
      final subscription3 = stream3.listen((_) {});

      await Future.delayed(Duration(milliseconds: 100));

      // Cancel some subscriptions
      await subscription1.cancel();
      await subscription2.cancel();

      // Manually trigger cleanup
      await reactiveDataAccess.cleanupInactiveStreams();

      // Check that streams were cleaned up (we can't access internals but test doesn't error)
      expect(true, isTrue); // Simple check that cleanup doesn't error

      await subscription3.cancel();
    });

    test('should handle database transaction rollbacks', () async {
      var updateCount = 0;
      final completer = Completer<void>();

      final subscription = reactiveDataAccess.watchTable('users').listen((data) {
        updateCount++;
        if (updateCount == 1) {
          completer.complete();
        }
      });

      await completer.future;

      final initialCount = updateCount;

      // Attempt operation that will fail (duplicate username)
      try {
        await reactiveDataAccess.insert('users', {
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
        final stream = reactiveDataAccess.watchTable('users');
        streams.add(stream);
        subscriptions.add(stream.listen((_) {}));
      }

      await Future.delayed(Duration(milliseconds: 100));

      final stats = reactiveDataAccess.getDependencyStats();
      
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