import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/files/filesystem_file_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  group('Unified save() method', () {
    late DeclarativeDatabase database;

    setUp(() async {
      final schema = SchemaBuilder()
          .table('users', (table) {
            table.text('name').notNull('');
            table.integer('age').notNull(0);
            table.text('email').lww();
            table.key(['system_id']).primary();
          })
          .build();

      database = await DeclarativeDatabase.open(
        ':memory:',
        databaseFactory: databaseFactory,
        schema: schema,
        fileRepository: FilesystemFileRepository('temp_test'),
      );
    });

    test('save() inserts a new record when created without system_id', () async {
      // Create a new record without system_id
      final record = GenericDbRecord({
        'name': 'Alice',
        'age': 30,
        'email': 'alice@example.com',
      }, 'users', database);

      // Verify it's marked as new
      expect(record.isNewRecord, isTrue);
      expect(record.systemId, isNull);

      // Save should perform an INSERT
      await record.save();

      // After save, should no longer be new and should have system_id
      expect(record.isNewRecord, isFalse);
      expect(record.systemId, isNotNull);

      // Verify the record exists in database
      final results = await database.queryTable('users');
      expect(results.length, 1);
      expect(results[0]['name'], 'Alice');
      expect(results[0]['age'], 30);
      expect(results[0]['email'], 'alice@example.com');
    });

    test('save() updates an existing record when loaded from database', () async {
      // First insert a record directly
      final systemId = await database.insert('users', {
        'name': 'Bob',
        'age': 25,
        'email': 'bob@example.com',
      });

      // Load the record from database
      final results = await database.queryTable('users', 
        where: 'system_id = ?', 
        whereArgs: [systemId]
      );
      final record = GenericDbRecord(results[0], 'users', database);

      // Verify it's marked as existing
      expect(record.isNewRecord, isFalse);
      expect(record.systemId, systemId);

      // Modify the record
      record.setValue('email', 'bob.updated@example.com');

      // Save should perform an UPDATE
      await record.save();

      // Verify the update
      final updatedResults = await database.queryTable('users',
        where: 'system_id = ?',
        whereArgs: [systemId]
      );
      expect(updatedResults.length, 1);
      expect(updatedResults[0]['name'], 'Bob'); // Unchanged
      expect(updatedResults[0]['age'], 25); // Unchanged
      expect(updatedResults[0]['email'], 'bob.updated@example.com'); // Updated
    });

    test('save() can be called multiple times on the same record', () async {
      // Create new record
      final record = GenericDbRecord({
        'name': 'Charlie',
        'age': 35,
        'email': 'charlie@example.com',
      }, 'users', database);

      // First save - inserts
      await record.save();
      expect(record.isNewRecord, isFalse);
      final systemId = record.systemId;
      expect(systemId, isNotNull);

      // Modify and save again - updates (using LWW column)
      record.setValue('email', 'charlie.updated@example.com');
      await record.save();

      // Verify update worked
      final results = await database.queryTable('users',
        where: 'system_id = ?',
        whereArgs: [systemId]
      );
      expect(results.length, 1);
      expect(results[0]['email'], 'charlie.updated@example.com');

      // Modify and save one more time - updates again
      record.setValue('email', 'charlie.new@example.com');
      await record.save();

      // Verify second update worked
      final results2 = await database.queryTable('users',
        where: 'system_id = ?',
        whereArgs: [systemId]
      );
      expect(results2.length, 1);
      expect(results2[0]['email'], 'charlie.new@example.com');
    });

    test('save() handles empty modifications on existing record', () async {
      // Insert and load a record
      final systemId = await database.insert('users', {
        'name': 'Diana',
        'age': 28,
        'email': 'diana@example.com',
      });

      final results = await database.queryTable('users',
        where: 'system_id = ?',
        whereArgs: [systemId]
      );
      final record = GenericDbRecord(results[0], 'users', database);

      // Call save without modifications
      await record.save();

      // Should complete without error
      expect(record.isNewRecord, isFalse);
      expect(record.systemId, systemId);
    });

    test('reload() maintains correct isNewRecord state', () async {
      // Insert a record
      final systemId = await database.insert('users', {
        'name': 'Eve',
        'age': 32,
        'email': 'eve@example.com',
      });

      // Load the record
      final results = await database.queryTable('users',
        where: 'system_id = ?',
        whereArgs: [systemId]
      );
      final record = GenericDbRecord(results[0], 'users', database);

      expect(record.isNewRecord, isFalse);

      // Reload the record
      await record.reload();

      // Should still not be a new record
      expect(record.isNewRecord, isFalse);
      expect(record.systemId, systemId);
    });

    test('isNewRecord getter provides correct state', () async {
      // New record
      final newRecord = GenericDbRecord({
        'name': 'Frank',
        'age': 40,
      }, 'users', database);
      expect(newRecord.isNewRecord, isTrue);

      // Existing record
      final systemId = await database.insert('users', {
        'name': 'Grace',
        'age': 29,
      });
      final results = await database.queryTable('users',
        where: 'system_id = ?',
        whereArgs: [systemId]
      );
      final existingRecord = GenericDbRecord(results[0], 'users', database);
      expect(existingRecord.isNewRecord, isFalse);
    });
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
