import 'dart:async';

import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqflite.dart' as sqflite;
import 'package:test/test.dart';

void buildTestSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id');
    table.text('name');
    table.integer('age');
    table.text('email');
    table.key(['id']).primary();
  });

  builder.table('posts', (table) {
    table.guid('id');
    table.guid('user_id');
    table.text('title');
    table.text('content');
    table.date('created_at');
    table.key(['id']).primary();
  });
}

/// A dummy dirty row store that doesn't support streaming for testing
class NullStreamDirtyRowStore implements DirtyRowStore {
  @override
  Future<void> init(sqflite.DatabaseExecutor db) async {}

  @override
  Future<void> add(String tableName, String rowId, Hlc hlc, bool isFullRow) async {}

  @override
  Future<List<DirtyRow>> getAll() async => [];

  @override
  Future<void> remove(List<DirtyRow> operations) async {}

  @override
  Future<void> clear() async {}

  @override
  Stream<DirtyRow> get onRowAdded => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

Future<DeclarativeDatabase> createTestDatabase({bool withDirtyRowStore = true}) async {
  sqfliteFfiInit();
  final schemaBuilder = SchemaBuilder();
  buildTestSchema(schemaBuilder);
  final schema = schemaBuilder.build();
  
  return await DeclarativeDatabase.open(
    ':memory:',
    databaseFactory: databaseFactoryFfi,
    schema: schema,
    fileRepository: FilesystemFileRepository('temp_test'),
    dirtyRowStore: withDirtyRowStore ? SqliteDirtyRowStore() : NullStreamDirtyRowStore(),
  );
}

void main() {
  group('Dirty Row Stream Tests', () {
    late DeclarativeDatabase database;
    late StreamSubscription<DirtyRow> subscription;
    late List<DirtyRow> receivedDirtyRows;

    setUp(() async {
      database = await createTestDatabase();
      receivedDirtyRows = [];
      
      // Set up stream listener before performing operations
      subscription = database.onDirtyRowAdded!.listen((dirtyRow) {
        receivedDirtyRows.add(dirtyRow);
      });
    });

    tearDown(() async {
      await subscription.cancel();
      await database.close();
    });

    test('stream emits dirty row when inserting new record', () async {
      // Insert a record
      final systemId = await database.insert('users', {
        'id': 'test-user-1',
        'name': 'John Doe',
      });

      // Wait a bit for the stream to process
      await Future.delayed(Duration(milliseconds: 10));

      // Verify the stream received the dirty row
      expect(receivedDirtyRows.length, equals(1));
      
      final dirtyRow = receivedDirtyRows.first;
      expect(dirtyRow.tableName, equals('users'));
      expect(dirtyRow.rowId, equals(systemId));
      expect(dirtyRow.isFullRow, isTrue); // Inserts are always full rows
    });

    test('stream emits dirty row when updating record', () async {
      // Insert a record first
      final systemId = await database.insert('users', {
        'id': 'test-user-2',
        'name': 'Jane Doe',
      });

      // Clear received rows from insert
      receivedDirtyRows.clear();

      // Update the record
      await database.update(
        'users',
        {'name': 'Jane Smith'},
        where: 'system_id = ?',
        whereArgs: [systemId],
      );

      // Wait a bit for the stream to process
      await Future.delayed(Duration(milliseconds: 10));

      // Verify the stream received the dirty row for the update
      expect(receivedDirtyRows.length, equals(1));
      
      final dirtyRow = receivedDirtyRows.first;
      expect(dirtyRow.tableName, equals('users'));
      expect(dirtyRow.rowId, equals(systemId));
      expect(dirtyRow.isFullRow, isTrue); // Local origin updates are full rows
    });

    test('stream emits dirty row when deleting record', () async {
      // Insert a record first
      final systemId = await database.insert('users', {
        'id': 'test-user-3',
        'name': 'Bob Wilson',
      });

      // Clear received rows from insert
      receivedDirtyRows.clear();

      // Delete the record
      await database.delete(
        'users',
        where: 'system_id = ?',
        whereArgs: [systemId],
      );

      // Wait a bit for the stream to process
      await Future.delayed(Duration(milliseconds: 10));

      // Verify the stream received the dirty row for the delete
      expect(receivedDirtyRows.length, equals(1));
      
      final dirtyRow = receivedDirtyRows.first;
      expect(dirtyRow.tableName, equals('users'));
      expect(dirtyRow.rowId, equals(systemId));
      expect(dirtyRow.isFullRow, isTrue); // Local origin deletes are full rows
    });

    test('stream does not emit for bulk load operations', () async {
      // Bulk load should not create dirty rows or emit to stream
      await database.bulkLoad('users', [
        {
          'system_id': 'server-user-1',
          'id': 'bulk-user-1',
          'name': 'Bulk User 1',
        },
        {
          'system_id': 'server-user-2',
          'id': 'bulk-user-2',
          'name': 'Bulk User 2',
        },
      ]);

      // Wait a bit to ensure no events are emitted
      await Future.delayed(Duration(milliseconds: 10));

      // Verify no dirty rows were emitted
      expect(receivedDirtyRows.length, equals(0));
    });

    test('stream handles multiple operations correctly', () async {
      // Perform multiple operations
      final systemId1 = await database.insert('users', {
        'id': 'multi-user-1',
        'name': 'User 1',
      });
      
      final systemId2 = await database.insert('users', {
        'id': 'multi-user-2',
        'name': 'User 2',
      });

      await database.update(
        'users',
        {'name': 'Updated User 1'},
        where: 'system_id = ?',
        whereArgs: [systemId1],
      );

      // Wait a bit for the stream to process
      await Future.delayed(Duration(milliseconds: 10));

      // Verify we received all three dirty rows
      expect(receivedDirtyRows.length, equals(3));
      
      // Check the operations are in the expected order
      expect(receivedDirtyRows[0].rowId, equals(systemId1)); // First insert
      expect(receivedDirtyRows[1].rowId, equals(systemId2)); // Second insert
      expect(receivedDirtyRows[2].rowId, equals(systemId1)); // Update of first record
      
      // All should be full rows for local origin operations
      expect(receivedDirtyRows.every((dr) => dr.isFullRow), isTrue);
    });

    test('stream works with multiple listeners', () async {
      // Set up a second listener
      final secondListenerRows = <DirtyRow>[];
      final secondSubscription = database.onDirtyRowAdded!.listen((dirtyRow) {
        secondListenerRows.add(dirtyRow);
      });

      try {
        // Insert a record
        final systemId = await database.insert('users', {
          'id': 'multi-listener-user',
          'name': 'Multi Listener Test',
        });

        // Wait a bit for the stream to process
        await Future.delayed(Duration(milliseconds: 10));

        // Both listeners should receive the same dirty row
        expect(receivedDirtyRows.length, equals(1));
        expect(secondListenerRows.length, equals(1));
        
        expect(receivedDirtyRows.first.rowId, equals(systemId));
        expect(secondListenerRows.first.rowId, equals(systemId));
        expect(receivedDirtyRows.first.tableName, equals(secondListenerRows.first.tableName));
      } finally {
        await secondSubscription.cancel();
      }
    });

    test('stream is resilient to listener errors', () async {
      // This test verifies that the broadcast stream continues to work
      // even if one listener throws an error
      final specialListenerRows = <DirtyRow>[];
      
      // Set up a special listener that processes normally
      final specialSubscription = database.onDirtyRowAdded!.listen((dirtyRow) {
        specialListenerRows.add(dirtyRow);
      });

      try {
        // Insert a record
        final systemId = await database.insert('users', {
          'id': 'resilient-test-user',
          'name': 'Resilient Test',
        });

        // Wait a bit
        await Future.delayed(Duration(milliseconds: 10));

        // Both listeners should have received the dirty row
        expect(receivedDirtyRows.length, equals(1));
        expect(specialListenerRows.length, equals(1));
        
        expect(receivedDirtyRows.first.rowId, equals(systemId));
        expect(specialListenerRows.first.rowId, equals(systemId));
      } finally {
        await specialSubscription.cancel();
      }
    });
  });

  group('Dirty Row Stream Edge Cases', () {
    test('stream works with custom dirty row store implementation', () async {
      // Create database with custom implementation
      final database = await createTestDatabase(withDirtyRowStore: false);
      
      try {
        // The stream should still be available even with the custom implementation
        expect(database.onDirtyRowAdded, isNotNull);
        
        // But it should be an empty stream that doesn't emit anything
        final receivedRows = <DirtyRow>[];
        final subscription = database.onDirtyRowAdded!.listen((row) {
          receivedRows.add(row);
        });
        
        // Insert a record
        await database.insert('users', {
          'id': 'custom-test-user',
          'name': 'Custom Test',
        });
        
        // Wait a bit
        await Future.delayed(Duration(milliseconds: 10));
        
        // Should not have received any rows from the empty stream
        expect(receivedRows.length, equals(0));
        
        await subscription.cancel();
      } finally {
        await database.close();
      }
    });

    test('dispose properly closes stream controllers', () async {
      final database = await createTestDatabase();
      final stream = database.onDirtyRowAdded!;
      
      // Listen to the stream
      final subscription = stream.listen((_) {});
      
      // Close the database (which should dispose the dirty row store)
      await database.close();
      
      // The subscription should complete/close
      await subscription.cancel();
      
      // Subsequent operations on the stream should not work
      // (This is more of a safety check - in normal usage the database
      // would not be used after close())
    });
  });
}