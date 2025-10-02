import 'package:test/test.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('LWW Column Restriction Tests', () {
    late DeclarativeDatabase database;

    setUp(() async {
      // Initialize sqflite_ffi for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('test_items', (table) {
        table.guid('id').notNull('');
        table.text('name').notNull('').lww(); // LWW column
        table.text('description').notNull(''); // Non-LWW column
        table.key(['id']).primary();
      });

      database = await DeclarativeDatabase.open(
        ':memory:',
        databaseFactory: databaseFactory,
        schema: schemaBuilder.build(),
        dirtyRowStore: SqliteDirtyRowStore(),
        recreateDatabase: true,
        fileRepository: FilesystemFileRepository('temp_test'),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('allows all columns to be set on new local rows', () async {
      // Insert a new row - should allow all columns
      final systemId = await database.insert('test_items', {
        'id': 'test-1',
        'name': 'Test Item',
        'description': 'Test Description',
      });

      // Verify the row was inserted correctly
      final results = await database.queryTable(
        'test_items',
        where: 'system_id = ?',
        whereArgs: [systemId],
      );
      expect(results.length, equals(1));
      expect(results[0]['name'], equals('Test Item'));
      expect(results[0]['description'], equals('Test Description'));
      expect(results[0]['system_is_local_origin'], equals(1));
    });

    test('restricts non-LWW column updates on server-origin rows', () async {
      // Simulate a row coming from server via bulkLoad
      await database.bulkLoad('test_items', [
        {
          'system_id': 'server-row-1',
          'id': 'test-2',
          'name': 'Server Item',
          'description': 'Server Description',
        },
      ]);

      // Verify the row is marked as non-local origin
      final results = await database.queryTable(
        'test_items',
        where: 'system_id = ?',
        whereArgs: ['server-row-1'],
      );
      expect(results.length, equals(1));
      expect(results[0]['system_is_local_origin'], equals(0));

      // Create a DbRecord from the server row
      final record = GenericDbRecord(results[0], 'test_items', database);

      // Should be able to update LWW column
      expect(() => record.setValue('name', 'Updated Name'), returnsNormally);

      // Should NOT be able to update non-LWW column
      expect(
        () => record.setValue('description', 'Updated Description'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(
              'is not marked as LWW and cannot be updated on rows that originated from server',
            ),
          ),
        ),
      );
    });

    test('allows all column updates on local-origin rows', () async {
      // Insert a new local row
      final systemId = await database.insert('test_items', {
        'id': 'test-3',
        'name': 'Local Item',
        'description': 'Local Description',
      });

      // Get the record
      final results = await database.queryTable(
        'test_items',
        where: 'system_id = ?',
        whereArgs: [systemId],
      );
      final record = GenericDbRecord(results[0], 'test_items', database);

      // Should be able to update both LWW and non-LWW columns
      expect(() => record.setValue('name', 'Updated Name'), returnsNormally);
      expect(
        () => record.setValue('description', 'Updated Description'),
        returnsNormally,
      );
    });

    test(
      'tracks full row for local origin and partial for server origin in dirty rows',
      () async {
        // Clear any existing dirty rows
        await database.dirtyRowStore?.clear();

        // Insert a local row
        final localSystemId = await database.insert('test_items', {
          'id': 'test-4',
          'name': 'Local Item',
          'description': 'Local Description',
        });

        // Insert a server row
        await database.bulkLoad('test_items', [
          {
            'system_id': 'server-row-2',
            'id': 'test-5',
            'name': 'Server Item',
            'description': 'Server Description',
          },
        ]);

        // Update the local row - should be marked as full row
        await database.update(
          'test_items',
          {'name': 'Updated Local'},
          where: 'system_id = ?',
          whereArgs: [localSystemId],
        );

        // Update the server row - should be marked as partial row
        await database.update(
          'test_items',
          {'name': 'Updated Server'},
          where: 'system_id = ?',
          whereArgs: ['server-row-2'],
        );

        // Check dirty rows
        final dirtyRows = await database.getDirtyRows();

        // Find the dirty rows for our test rows
        final localDirtyRow = dirtyRows.firstWhere(
          (r) => r.rowId == localSystemId,
        );
        final serverDirtyRow = dirtyRows.firstWhere(
          (r) => r.rowId == 'server-row-2',
        );

        // Local origin row should be marked as full row
        expect(localDirtyRow.isFullRow, isTrue);

        // Server origin row should be marked as partial row (LWW only)
        expect(serverDirtyRow.isFullRow, isFalse);
      },
    );
  });
}

/// A generic DbRecord implementation for testing
class GenericDbRecord extends DbRecord {
  GenericDbRecord(
    Map<String, Object?> data,
    String tableName,
    DeclarativeDatabase database,
  ) : super(data, tableName, database);
}
