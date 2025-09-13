import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Test suite for pull-to-refresh functionality
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
    
    schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('email', (col) => col.notNull()))
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .integer('user_id', (col) => col.notNull())
          .text('title', (col) => col.notNull()));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);

    // Insert initial data
    await dataAccess.insert('users', {'name': 'Alice', 'email': 'alice@test.com'});
    await dataAccess.insert('posts', {'user_id': 1, 'title': 'First Post'});
  });

  tearDown(() async {
    await dataAccess.dispose();
    await database.close();
  });

  group('Pull-to-Refresh Functionality', () {
    test('refreshStream should refresh a specific stream', () async {
      var updateCount = 0;
      List<Map<String, dynamic>>? lastData;

      final query = QueryBuilder().selectAll().from('users');
      final stream = dataAccess.watch(query, streamId: 'test_users_stream');
      final subscription = stream.listen((data) {
        updateCount++;
        lastData = data;
      });

      // Wait for initial data
      await Future.delayed(Duration(milliseconds: 500));
      expect(updateCount, equals(1));
      expect(lastData!.length, equals(1));

      // Manually refresh the stream (simulating pull-to-refresh)
      await dataAccess.refreshStream('test_users_stream');

      // Wait for refresh to complete
      await Future.delayed(Duration(milliseconds: 200));
      expect(updateCount, equals(2)); // Should have received another update

      await subscription.cancel();
    });

    test('refreshTable should refresh all streams watching a table', () async {
      var usersUpdateCount = 0;
      var postsUpdateCount = 0;

      // Create streams for different tables
      final usersQuery = QueryBuilder().selectAll().from('users');
      final postsQuery = QueryBuilder().selectAll().from('posts');
      
      final usersStream = dataAccess.watch(usersQuery, streamId: 'users_stream');
      final postsStream = dataAccess.watch(postsQuery, streamId: 'posts_stream');

      final usersSubscription = usersStream.listen((data) => usersUpdateCount++);
      final postsSubscription = postsStream.listen((data) => postsUpdateCount++);

      // Wait for initial data
      await Future.delayed(Duration(milliseconds: 500));
      expect(usersUpdateCount, equals(1));
      expect(postsUpdateCount, equals(1));

      // Refresh only users table
      await dataAccess.refreshTable('users');

      // Wait for refresh to complete
      await Future.delayed(Duration(milliseconds: 200));
      expect(usersUpdateCount, greaterThan(1)); // Users stream should be refreshed
      
      await usersSubscription.cancel();
      await postsSubscription.cancel();
    });

    test('refreshAll should refresh all active streams', () async {
      var usersUpdateCount = 0;
      var postsUpdateCount = 0;

      // Create streams for different tables
      final usersQuery = QueryBuilder().selectAll().from('users');
      final postsQuery = QueryBuilder().selectAll().from('posts');
      
      final usersStream = dataAccess.watch(usersQuery, streamId: 'all_users_stream');
      final postsStream = dataAccess.watch(postsQuery, streamId: 'all_posts_stream');

      final usersSubscription = usersStream.listen((data) => usersUpdateCount++);
      final postsSubscription = postsStream.listen((data) => postsUpdateCount++);

      // Wait for initial data
      await Future.delayed(Duration(milliseconds: 500));
      expect(usersUpdateCount, equals(1));
      expect(postsUpdateCount, equals(1));

      // Refresh all streams
      await dataAccess.refreshAll();

      // Wait for refresh to complete
      await Future.delayed(Duration(milliseconds: 200));
      expect(usersUpdateCount, greaterThan(1)); // Users stream should be refreshed
      expect(postsUpdateCount, greaterThan(1)); // Posts stream should be refreshed

      await usersSubscription.cancel();
      await postsSubscription.cancel();
    });

    test('pull-to-refresh pattern with manual refresh after external data change', () async {
      var updateCount = 0;
      List<Map<String, dynamic>>? lastData;

      final query = QueryBuilder().selectAll().from('users');
      final stream = dataAccess.watch(query, streamId: 'ptr_users_stream');
      final subscription = stream.listen((data) {
        updateCount++;
        lastData = data;
      });

      // Wait for initial data
      await Future.delayed(Duration(milliseconds: 500));
      expect(updateCount, equals(1));
      expect(lastData!.length, equals(1));

      // Simulate external data change (e.g., from server sync)
      // This would normally be done through a different database connection
      // or by bypassing the reactive data access layer
      await dataAccess.insert('users', {'name': 'Bob', 'email': 'bob@test.com'});

      // The stream might not automatically detect this change since it bypassed reactive layer
      // So user does pull-to-refresh
      await dataAccess.refreshTable('users');

      // Wait for refresh to complete
      await Future.delayed(Duration(milliseconds: 200));
      expect(lastData!.length, equals(2)); // Should now see both users

      await subscription.cancel();
    });
  });
}