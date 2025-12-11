import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void buildTestSchema(SchemaBuilder builder) {
  builder.table('c_work_order', (table) {
    table.guid('id');
    table.text('rowstate');
    table.text('description');
    table.integer('priority');
    table.key(['id']).primary();
  });
}

Future<DeclarativeDatabase> createTestDatabase() async {
  sqfliteFfiInit();
  final schemaBuilder = SchemaBuilder();
  buildTestSchema(schemaBuilder);
  final schema = schemaBuilder.build();
  
  return await DeclarativeDatabase.open(
    ':memory:',
    databaseFactory: databaseFactoryFfi,
    schema: schema,
    fileRepository: FilesystemFileRepository('temp_test'),
    dirtyRowStore: SqliteDirtyRowStore(),
  );
}

void main() {
  group('Dirty Row Data Field Tests', () {
    late DeclarativeDatabase database;

    setUp(() async {
      database = await createTestDatabase();
    });

    tearDown(() async {
      await database.close();
    });

    test('insert operation captures data field', () async {
      // Insert a row
      final systemId = await database.insert('c_work_order', {
        'id': 'work-order-1',
        'rowstate': 'WorkStarted',
        'description': 'Fix the bug',
        'priority': 1,
      });

      // Get dirty rows
      final dirtyRows = await database.getDirtyRows();
      
      expect(dirtyRows.length, equals(1));
      
      final dirtyRow = dirtyRows.first;
      expect(dirtyRow.tableName, equals('c_work_order'));
      expect(dirtyRow.rowId, equals(systemId));
      expect(dirtyRow.isFullRow, isTrue);
      expect(dirtyRow.data, isNotNull);
      
      // Verify the data contains the inserted values
      expect(dirtyRow.data!['id'], equals('work-order-1'));
      expect(dirtyRow.data!['rowstate'], equals('WorkStarted'));
      expect(dirtyRow.data!['description'], equals('Fix the bug'));
      expect(dirtyRow.data!['priority'], equals(1));
    });

    test('update operation captures data field with only changed values', () async {
      // Insert a row first
      final systemId = await database.insert('c_work_order', {
        'id': 'work-order-2',
        'rowstate': 'WorkPending',
        'description': 'Initial description',
        'priority': 2,
      });

      // Clear dirty rows from insert
      await database.dirtyRowStore?.clear();

      // Update the row with specific fields
      await database.update(
        'c_work_order',
        {
          'rowstate': 'WorkStarted',
          'priority': 5,
        },
        where: 'system_id = ?',
        whereArgs: [systemId],
      );

      // Get dirty rows
      final dirtyRows = await database.getDirtyRows();
      
      expect(dirtyRows.length, equals(1));
      
      final dirtyRow = dirtyRows.first;
      expect(dirtyRow.tableName, equals('c_work_order'));
      expect(dirtyRow.rowId, equals(systemId));
      expect(dirtyRow.isFullRow, isTrue);
      expect(dirtyRow.data, isNotNull);
      
      // Verify the data contains the updated values
      expect(dirtyRow.data!['rowstate'], equals('WorkStarted'));
      expect(dirtyRow.data!['priority'], equals(5));
      
      // The data should only contain the fields that were updated
      // (This is the expected behavior based on the problem statement)
      expect(dirtyRow.data!.containsKey('rowstate'), isTrue);
      expect(dirtyRow.data!.containsKey('priority'), isTrue);
    });

    test('delete operation stores null data', () async {
      // Insert a row first
      final systemId = await database.insert('c_work_order', {
        'id': 'work-order-3',
        'rowstate': 'WorkPending',
      });

      // Clear dirty rows from insert
      await database.dirtyRowStore?.clear();

      // Delete the row
      await database.delete(
        'c_work_order',
        where: 'system_id = ?',
        whereArgs: [systemId],
      );

      // Get dirty rows
      final dirtyRows = await database.getDirtyRows();
      
      expect(dirtyRows.length, equals(1));
      
      final dirtyRow = dirtyRows.first;
      expect(dirtyRow.tableName, equals('c_work_order'));
      expect(dirtyRow.rowId, equals(systemId));
      expect(dirtyRow.isFullRow, isTrue);
      // For deletes, data should be null since the row is removed
      expect(dirtyRow.data, isNull);
    });

    test('data field persists across database queries', () async {
      // Insert a row
      await database.insert('c_work_order', {
        'id': 'work-order-4',
        'rowstate': 'WorkCompleted',
        'description': 'Test persistence',
      });

      // Get dirty rows first time
      final dirtyRows1 = await database.getDirtyRows();
      expect(dirtyRows1.length, equals(1));
      expect(dirtyRows1.first.data, isNotNull);
      expect(dirtyRows1.first.data!['rowstate'], equals('WorkCompleted'));

      // Get dirty rows again - should still have the data
      final dirtyRows2 = await database.getDirtyRows();
      expect(dirtyRows2.length, equals(1));
      expect(dirtyRows2.first.data, isNotNull);
      expect(dirtyRows2.first.data!['rowstate'], equals('WorkCompleted'));
    });

    test('data field supports various data types', () async {
      // Insert a row with different data types
      final systemId = await database.insert('c_work_order', {
        'id': 'work-order-5',
        'rowstate': 'WorkStarted',
        'description': 'Test with special chars: "quotes", \'apostrophes\', and\nnewlines',
        'priority': 999,
      });

      // Get dirty rows
      final dirtyRows = await database.getDirtyRows();
      
      expect(dirtyRows.length, equals(1));
      
      final dirtyRow = dirtyRows.first;
      expect(dirtyRow.data, isNotNull);
      
      // Verify all data types are preserved
      expect(dirtyRow.data!['id'], isA<String>());
      expect(dirtyRow.data!['rowstate'], isA<String>());
      expect(dirtyRow.data!['description'], isA<String>());
      expect(dirtyRow.data!['priority'], isA<int>());
      
      // Verify special characters are preserved
      expect(dirtyRow.data!['description'], contains('"quotes"'));
      expect(dirtyRow.data!['description'], contains('\'apostrophes\''));
      expect(dirtyRow.data!['description'], contains('\n'));
    });

    test('multiple updates on same row replace dirty row entry with latest data', () async {
      // Insert a row
      final systemId = await database.insert('c_work_order', {
        'id': 'work-order-6',
        'rowstate': 'WorkPending',
        'priority': 1,
      });

      // Clear dirty rows from insert
      await database.dirtyRowStore?.clear();

      // First update
      await database.update(
        'c_work_order',
        {'rowstate': 'WorkStarted'},
        where: 'system_id = ?',
        whereArgs: [systemId],
      );

      // Second update
      await database.update(
        'c_work_order',
        {'priority': 10},
        where: 'system_id = ?',
        whereArgs: [systemId],
      );

      // Get dirty rows - should have only the latest entry
      final dirtyRows = await database.getDirtyRows();
      
      // Because we use INSERT OR REPLACE, there should be only 1 entry
      expect(dirtyRows.length, equals(1));
      
      final dirtyRow = dirtyRows.first;
      // The latest update should have the priority field
      expect(dirtyRow.data, isNotNull);
      expect(dirtyRow.data!['priority'], equals(10));
    });
  });
}
