import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Minimal test to verify DbRecord basic functionality
void main() {
  late DeclarativeDatabase db;

  Schema getSchema() {
    final schemaBuilder = SchemaBuilder();
    schemaBuilder.table('test_table', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.integer('age').notNull(0);
      table.date('created_at');
      table.key(['id']).primary();
    });
    return schemaBuilder.build();
  }

  setUpAll(() async {
    db = await setupTestDatabase(schema: getSchema());
  });

  setUp(() async {
    await clearDatabase(db.db);
  });

  tearDownAll(() async {
    await db.close();
  });

  test('DbRecord basic functionality works', () async {
    // Insert test data using traditional API
    await db.insert('test_table', {
      'id': 1,
      'name': 'Test User',
      'age': 25,
      'created_at': DateTime(2023, 1, 1).toIso8601String(),
    });

    // Query using DbRecord API  
    final records = await db.queryTableRecords('test_table');
    
    expect(records.length, 1);
    
    final record = records.first;
    
    // Test typed getters
    expect(record.getValue<int>('id'), 1);
    expect(record.getValue<String>('name'), 'Test User');
    expect(record.getValue<int>('age'), 25);
    
    // Test DateTime conversion
    final createdAt = record.getValue<DateTime>('created_at');
    expect(createdAt?.year, 2023);
    expect(createdAt?.month, 1);
    expect(createdAt?.day, 1);
    
    // Test system columns
    expect(record.systemId, isNotNull);
    expect(record.systemCreatedAt, isA<DateTime>());
    
    // Test setters and dirty tracking
    expect(record.modifiedFields.isEmpty, true);
    
    record.setValue('name', 'Updated User');
    record.setValue('age', 26);
    
    expect(record.modifiedFields, containsAll(['name', 'age']));
    expect(record.getValue<String>('name'), 'Updated User');
    expect(record.getValue<int>('age'), 26);
    
    // Test save
    await record.save();
    expect(record.modifiedFields.isEmpty, true);
    
    // Verify changes were persisted
    final updatedRecords = await db.queryTableRecords('test_table');
    final updatedRecord = updatedRecords.first;
    
    expect(updatedRecord.getValue<String>('name'), 'Updated User');
    expect(updatedRecord.getValue<int>('age'), 26);
  });

  test('DbRecord creation and insertion works', () async {
    // Create a new record
    final newRecord = RecordFactory.fromMap({
      'id': 2,
      'name': 'New User',
      'age': 30,
      'created_at': DateTime.now().toIso8601String(),
    }, 'test_table', db);

    // Insert it
    await newRecord.insert();

    // Verify it exists
    final records = await db.queryTableRecords('test_table');
    expect(records.length, 1);
    
    final record = records.first;
    expect(record.getValue<String>('name'), 'New User');
    expect(record.getValue<int>('age'), 30);
    expect(record.systemId, isNotNull);
  });

  test('DbRecord delete works', () async {
    // Insert and then delete
    await db.insert('test_table', {
      'id': 3,
      'name': 'To Delete',
      'age': 40,
    });

    final records = await db.queryTableRecords('test_table');
    expect(records.length, 1);

    await records.first.delete();

    final remainingRecords = await db.queryTableRecords('test_table');
    expect(remainingRecords.isEmpty, true);
  });

  test('Error handling works correctly', () async {
    await db.insert('test_table', {
      'id': 4,
      'name': 'Error Test',
      'age': 35,
    });

    final records = await db.queryTableRecords('test_table');
    final record = records.first;

    // Test invalid column access
    expect(
      () => record.getValue('nonexistent_column'),
      throwsArgumentError,
    );

    // Test save/delete without system_id
    final orphanRecord = RecordFactory.fromMap({
      'name': 'Orphan'
    }, 'test_table', db);

    expect(() => orphanRecord.save(), throwsStateError);
    expect(() => orphanRecord.delete(), throwsStateError);
  });
}