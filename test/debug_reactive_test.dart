import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Debug test to figure out why reactive streams aren't working
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

    // Insert initial data like the failing test
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

  test('debug reactive stream with insert', () async {
    print('Creating stream...');
    final stream = dataAccess.watchTable('users');
    
    print('Stream created, adding listener...');
    var updateCount = 0;
    List<Map<String, dynamic>>? lastData;
    
    final subscription = stream.listen((data) {
      updateCount++;
      lastData = data;
      print('Stream update #$updateCount: ${data.length} records');
    });

    print('Waiting for initial data...');
    await Future.delayed(Duration(milliseconds: 500));
    
    print('Update count after initial: $updateCount');
    
    print('Inserting new user...');
    await dataAccess.insert('users', {
      'username': 'bob2',
      'email': 'bob2@example.com',
      'age': 25,
      'status': 'active',
    });
    
    print('Waiting after insert...');
    await Future.delayed(Duration(milliseconds: 500));
    
    print('Final update count: $updateCount');
    print('Final data: $lastData');
    
    // Check dependency stats
    final stats = dataAccess.getDependencyStats();
    print('Dependency stats: $stats');

    await subscription.cancel();
    
    // Should have at least 2 updates: initial + insert
    expect(updateCount, greaterThanOrEqualTo(2), 
      reason: 'Stream should emit initial data and update after insert');
  });

  test('exact replica of failing test', () async {
    final completer = Completer<List<Map<String, dynamic>>>();
    var updateCount = 0;

    print('Creating subscription...');
    final subscription = dataAccess.watchTable('users').listen((data) {
      updateCount++;
      print('📢 Stream update #$updateCount: ${data.length} records');
      if (updateCount == 2) { // Skip initial load, wait for insert
        print('🎯 Completing completer with $updateCount updates');
        completer.complete(data);
      }
    });

    // Wait for initial load
    print('⏳ Waiting for initial load...');
    await Future.delayed(Duration(milliseconds: 100));
    print('📊 After initial delay: $updateCount updates');

    // Insert new user - should trigger update
    print('➕ Inserting new user...');
    await dataAccess.insert('users', {
      'username': 'bob',
      'email': 'bob@example.com',
      'age': 25,
      'status': 'active',
    });
    print('✅ Insert completed');

    print('⏳ Waiting for completer...');
    final result = await completer.future.timeout(Duration(seconds: 2));
    print('🏆 Completer completed successfully');
    
    expect(updateCount, equals(2));
    expect(result.length, equals(2)); // 1 initial + 1 new

    await subscription.cancel();
  });
}