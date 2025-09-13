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
          .text('name', (col) => col.notNull()));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);

    // Insert initial data
    await dataAccess.insert('users', {'name': 'Alice'});
  });

  tearDown(() async {
    await dataAccess.dispose();
    await database.close();
  });

  test('debug reactive stream creation', () async {
    print('Creating stream...');
    final stream = dataAccess.watchTable('users');
    
    print('Stream created, adding listener...');
    var updateCount = 0;
    List<Map<String, dynamic>>? lastData;
    
    final subscription = stream.listen((data) {
      updateCount++;
      lastData = data;
      print('Stream update #$updateCount: $data');
    });

    print('Waiting for initial data...');
    await Future.delayed(Duration(milliseconds: 500));
    
    print('Update count: $updateCount');
    print('Last data: $lastData');
    
    if (updateCount == 0) {
      print('No updates received. Testing direct DataAccess...');
      final directData = await dataAccess.getAll('users');
      print('Direct query result: $directData');
    }

    await subscription.cancel();
    
    // Basic assertion
    expect(updateCount, greaterThan(0), reason: 'Stream should emit at least one update');
  });

  test('debug simple data access', () async {
    print('Testing direct data access...');
    final users = await dataAccess.getAll('users');
    print('Users from direct query: $users');
    expect(users.length, equals(1));
  });
}