import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/declarative_sqlite.dart';

void main() {
  group('Debug INSERT Notification', () {
    late Database database;
    late DataAccess dataAccess;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      database = await openDatabase(':memory:');
      
      final schema = SchemaBuilder()
        .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('username', (col) => col.notNull())
          .text('email')
          .integer('age')
          .text('status')
          .text('created_at', (col) => col.notNull()));

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
      
      dataAccess = await DataAccess.create(database: database, schema: schema);
      
      // Insert initial test data
      await dataAccess.insert('users', {
        'username': 'alice',
        'email': 'alice@example.com', 
        'age': 30,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      });
    });

    tearDown(() async {
      await dataAccess.dispose();
      await database.close();
    });

    test('should debug INSERT notification flow', () async {
      print('Starting debug test...');
      
      var updateCount = 0;
      final updates = <List<Map<String, dynamic>>>[];
      final completer = Completer<List<Map<String, dynamic>>>();

      final query = QueryBuilder().selectAll().from('users');
      print('Created query: ${query.toSql()}');
      
      final subscription = dataAccess.watch(query).listen((data) {
        updateCount++;
        updates.add(data);
        print('Stream update #$updateCount: ${data.length} records');
        
        if (updateCount == 2) { // Wait for the insert to trigger
          completer.complete(data);
        }
      });

      print('Waiting for initial data...');
      await Future.delayed(Duration(milliseconds: 200));
      print('Update count after initial delay: $updateCount');
      
      // Check dependency stats
      final stats = dataAccess.getDependencyStats();
      print('Dependency stats: $stats');

      print('Inserting new user...');
      await dataAccess.insert('users', {
        'username': 'bob',
        'email': 'bob@example.com',
        'age': 25,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      });
      
      print('Insert completed, waiting for stream update...');
      try {
        final result = await completer.future.timeout(Duration(seconds: 3));
        print('Final result: ${result.length} records');
        expect(result.length, equals(2));
        expect(updateCount, equals(2));
      } catch (e) {
        print('Test failed with error: $e');
        print('Final update count: $updateCount');
        print('All updates received: ${updates.map((u) => u.length).toList()}');
        rethrow;
      }

      await subscription.cancel();
    });
  });
}