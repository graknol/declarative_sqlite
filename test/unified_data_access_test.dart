import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Unified DataAccess Tests', () {
    late Database database;
    late SchemaBuilder schema;

    setUp(() async {
      database = await openDatabase(':memory:');
      
      schema = SchemaBuilder()
        .table('tasks', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .integer('hours', (col) => col.lww())
          .real('rate', (col) => col.lww())
          .text('notes', (col) => col.lww()));

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
    });

    tearDown(() async {
      await database.close();
    });

    test('can create DataAccess without LWW support', () async {
      final dataAccess = DataAccess(database: database, schema: schema);
      expect(dataAccess.lwwEnabled, isFalse);

      // Should be able to insert normal data
      final id = await dataAccess.insert('tasks', {
        'title': 'Test Task',
        'hours': 5,
        'rate': 25.0,
        'notes': 'Test notes',
      });

      expect(id, isNotNull);
      final task = await dataAccess.getByPrimaryKey('tasks', id);
      expect(task!['title'], equals('Test Task'));
    });

    test('can create DataAccess with LWW support', () async {
      final dataAccess = await DataAccess.createWithLWW(
        database: database, 
        schema: schema
      );
      expect(dataAccess.lwwEnabled, isTrue);

      // First insert a row
      final id = await dataAccess.insert('tasks', {
        'title': 'LWW Test Task',
        'hours': 5,
      });

      // Then update an LWW column
      await dataAccess.updateLWWColumn('tasks', id, 'hours', 8);
      final hours = await dataAccess.getLWWColumnValue('tasks', id, 'hours');
      expect(hours, equals(8));
    });

    test('bulkLoad supports per-row timestamps', () async {
      final dataAccess = await DataAccess.createWithLWW(
        database: database, 
        schema: schema
      );

      final timestamp1 = '1000';
      final timestamp2 = '2000';
      
      final dataset = [
        {'id': 1, 'title': 'Task 1', 'hours': 10, 'rate': 25.0, 'notes': 'First task'},
        {'id': 2, 'title': 'Task 2', 'hours': 8, 'rate': 30.0, 'notes': 'Second task'},
      ];

      final perRowTimestamps = [
        {'hours': timestamp1, 'rate': timestamp1, 'notes': timestamp1},
        {'hours': timestamp2, 'rate': timestamp2, 'notes': timestamp2},
      ];

      final result = await dataAccess.bulkLoad('tasks', dataset, 
        options: BulkLoadOptions(
          lwwTimestamps: perRowTimestamps,
          isFromServer: true,
        )
      );

      expect(result.rowsInserted, equals(2));
      expect(result.rowsSkipped, equals(0));

      // Verify data was inserted correctly
      final task1 = await dataAccess.getByPrimaryKey('tasks', 1);
      expect(task1!['title'], equals('Task 1'));
      expect(task1['hours'], equals(10));

      final task2 = await dataAccess.getByPrimaryKey('tasks', 2);
      expect(task2!['title'], equals('Task 2'));
      expect(task2['hours'], equals(8));
    });

    test('bulkLoad validates per-row timestamps', () async {
      final dataAccess = await DataAccess.createWithLWW(
        database: database, 
        schema: schema
      );

      final dataset = [
        {'id': 1, 'title': 'Task 1', 'hours': 10},
      ];

      // Missing timestamps should throw error
      expect(() async => await dataAccess.bulkLoad('tasks', dataset), 
        throwsA(isA<ArgumentError>()));
    });

    test('bulkLoad supports legacy single timestamps', () async {
      final dataAccess = await DataAccess.createWithLWW(
        database: database, 
        schema: schema
      );

      final dataset = [
        {'id': 1, 'title': 'Task 1', 'hours': 10, 'rate': 25.0},
        {'id': 2, 'title': 'Task 2', 'hours': 8, 'rate': 30.0},
      ];

      final result = await dataAccess.bulkLoad('tasks', dataset, 
        options: BulkLoadOptions(
          lwwTimestamps: [
            {'hours': '1000', 'rate': '1000'},  // Row 1 timestamps
            {'hours': '1000', 'rate': '1000'},  // Row 2 timestamps
          ],
          isFromServer: true,
        )
      );

      expect(result.rowsInserted, equals(2));
    });
  });
}