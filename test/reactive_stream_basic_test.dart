import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Basic reactive stream test to validate functionality
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
    
    schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('username', (col) => col.notNull().unique())
          .text('email', (col) => col.notNull())
          .integer('age')
          .text('status', (col) => col.notNull()));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);
    reactiveDataAccess = ReactiveDataAccess(
      dataAccess: dataAccess,
      schema: schema,
    );

    // Insert test data
    await dataAccess.insert('users', {
      'username': 'alice',
      'email': 'alice@example.com',
      'age': 30,
      'status': 'active',
    });
  });

  tearDown(() async {
    await reactiveDataAccess.dispose();
    await database.close();
  });

  group('Basic Reactive Functionality', () {
    test('should trigger stream on table changes', () async {
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
        'username': 'bob',
        'email': 'bob@example.com',
        'age': 25,
        'status': 'active',
      });

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(2)); // 1 initial + 1 new

      await subscription.cancel();
    });

    test('bulkLoad should trigger streams', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final subscription = reactiveDataAccess.watchTable('users').listen((data) {
        updateCount++;
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 100));

      // Bulk load data - should trigger stream
      await reactiveDataAccess.bulkLoad('users', [
        {'username': 'charlie', 'email': 'charlie@example.com', 'age': 35, 'status': 'active'},
        {'username': 'david', 'email': 'david@example.com', 'age': 28, 'status': 'inactive'},
      ]);

      final result = await completer.future.timeout(Duration(seconds: 2));
      expect(updateCount, equals(2));
      expect(result.length, equals(3)); // 1 initial + 2 bulk

      await subscription.cancel();
    });

    test('should get dependency statistics', () async {
      final stream1 = reactiveDataAccess.watchTable('users');
      final stream2 = reactiveDataAccess.watchTable('users', where: 'status = ?', whereArgs: ['active']);
      
      final subscription1 = stream1.listen((_) {});
      final subscription2 = stream2.listen((_) {});

      await Future.delayed(Duration(milliseconds: 100));

      final stats = reactiveDataAccess.getDependencyStats();
      expect(stats.totalStreams, greaterThan(0));
      expect(stats.totalDependencies, greaterThan(0));

      await subscription1.cancel();
      await subscription2.cancel();
    });
  });
}