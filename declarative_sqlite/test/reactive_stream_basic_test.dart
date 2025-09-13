import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Basic reactive stream test to validate functionality
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
          .text('username', (col) => col.notNull().unique())
          .text('email', (col) => col.notNull())
          .integer('age')
          .text('status', (col) => col.notNull()));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);

    // Insert test data
    await dataAccess.insert('users', {
      'username': 'alice',
      'email': 'alice@example.com',
      'age': 30,
      'status': 'active',
    });
  });

  tearDown(() async {
    await dataAccess.dispose();
    await database.close();
  });

  group('Basic Reactive Functionality', () {
    test('should trigger stream on table changes', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      print('🔧 DEBUG: Creating watch stream with QueryBuilder');
      final query = QueryBuilder().selectAll().from('users');
      final streamResult = dataAccess.watch(query);
      print('🔧 DEBUG: Stream created, type: ${streamResult.runtimeType}');
      
      final subscription = streamResult.listen((data) {
        updateCount++;
        print('🔧 DEBUG: Stream update #$updateCount: ${data.length} records');
        if (updateCount == 2) { // Skip initial load, wait for insert
          print('🔧 DEBUG: Completing completer with data: $data');
          completer.complete(data);
        }
      });

      // Wait for initial load
      print('🔧 DEBUG: Waiting for initial load');
      await Future.delayed(Duration(milliseconds: 200));
      print('🔧 DEBUG: After delay, update count: $updateCount');

      // Insert new user - should trigger update
      print('🔧 DEBUG: Inserting new user');
      await dataAccess.insert('users', {
        'username': 'bob',
        'email': 'bob@example.com',
        'age': 25,
        'status': 'active',
      });
      print('🔧 DEBUG: Insert completed');

      // Wait a bit longer for the stream to be notified
      print('🔧 DEBUG: Waiting for stream notification');
      await Future.delayed(Duration(milliseconds: 200));
      print('🔧 DEBUG: After insert delay, update count: $updateCount');

      print('🔧 DEBUG: Waiting for completer timeout');
      final result = await completer.future.timeout(Duration(seconds: 5));
      expect(updateCount, equals(2));
      expect(result.length, equals(2)); // 1 initial + 1 new

      await subscription.cancel();
    });

    test('bulkLoad should trigger streams', () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      var updateCount = 0;

      final query = QueryBuilder().selectAll().from('users');
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        print('🔧 DEBUG: bulkLoad test - Stream update #$updateCount: ${data.length} records');
        if (updateCount == 2) {
          completer.complete(data);
        }
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Bulk load data - should trigger stream
      print('🔧 DEBUG: bulkLoad test - Starting bulk load');
      await dataAccess.bulkLoad('users', [
        {'username': 'charlie', 'email': 'charlie@example.com', 'age': 35, 'status': 'active'},
        {'username': 'david', 'email': 'david@example.com', 'age': 28, 'status': 'inactive'},
      ]);
      print('🔧 DEBUG: bulkLoad test - Bulk load completed');

      // Wait for stream notification
      await Future.delayed(Duration(milliseconds: 200));

      final result = await completer.future.timeout(Duration(seconds: 5));
      expect(updateCount, equals(2));
      expect(result.length, equals(3)); // 1 initial + 2 bulk

      await subscription.cancel();
    });

    test('should get dependency statistics', () async {
      final query1 = QueryBuilder().selectAll().from('users');
      final query2 = QueryBuilder().selectAll().from('users').where('status = \'active\'');
      
      final stream1 = dataAccess.watch(query1);
      final stream2 = dataAccess.watch(query2);
      
      final subscription1 = stream1.listen((_) {});
      final subscription2 = stream2.listen((_) {});

      await Future.delayed(Duration(milliseconds: 100));

      final stats = dataAccess.getDependencyStats();
      expect(stats.totalStreams, greaterThan(0));
      expect(stats.totalDependencies, greaterThan(0));

      await subscription1.cancel();
      await subscription2.cancel();
    });
  });
}