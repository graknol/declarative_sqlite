import 'package:test/test.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('should allow defining primary key on system_id column', () async {
    sqfliteFfiInit();
    
    final schemaBuilder = SchemaBuilder();
    
    // This should work - user explicitly defining system_id as primary key
    schemaBuilder.table('users', (table) {
      table.guid('id').notNull('');
      table.text('name').notNull('');
      table.integer('age').notNull(0);
      // This should be allowed even though system_id is auto-generated
      table.key(['system_id']).primary();
    });
    
    final schema = schemaBuilder.build();
    
    // Verify the schema builds correctly
    final userTable = schema.tables.firstWhere((t) => t.name == 'users');
    expect(userTable.name, equals('users'));
    
    // Check that system_id column exists
    final systemIdColumn = userTable.columns.firstWhere((c) => c.name == 'system_id');
    expect(systemIdColumn.name, equals('system_id'));
    expect(systemIdColumn.logicalType, equals('guid'));
    
    // Check that primary key is defined on system_id
    final primaryKey = userTable.keys.firstWhere((k) => k.isPrimary);
    expect(primaryKey.columns, equals(['system_id']));
    
    // Print schema for debugging
    print('Schema built successfully with system_id primary key');
    print('Columns: ${userTable.columns.map((c) => '${c.name}(${c.logicalType})').join(', ')}');
    print('Keys: ${userTable.keys.map((k) => '${k.columns.join(",")} (${k.type})').join('; ')}');
    
    // Verify we can create a database with this schema
    final database = await DeclarativeDatabase.open(
      ':memory:',
      databaseFactory: databaseFactoryFfi,
      schema: schema,
      fileRepository: FilesystemFileRepository('temp_test'),
    );
    
    // Insert should work
    final systemId = await database.insert('users', {
      'id': 'user-1',
      'name': 'John Doe',
      'age': 30,
    });
    
    expect(systemId, isA<String>());
    
    // Query back to verify the data
    final results = await database.queryTable('users');
    expect(results.length, equals(1));
    final user = results.first;
    expect(user['system_id'], equals(systemId));
    expect(user['id'], equals('user-1'));
    expect(user['name'], equals('John Doe'));
    
    await database.close();
  });
  
  test('should allow mixed keys with system_id and user columns', () async {
    sqfliteFfiInit();
    
    final schemaBuilder = SchemaBuilder();
    
    // Test composite key with system_id and user column
    schemaBuilder.table('user_sessions', (table) {
      table.text('session_token').notNull('');
      table.date('created_at').notNull('1970-01-01');
      // Composite primary key with system_id and user column
      table.key(['system_id', 'session_token']).primary();
    });
    
    final schema = schemaBuilder.build();
    
    final userSessionsTable = schema.tables.firstWhere((t) => t.name == 'user_sessions');
    
    // Check that primary key includes both system_id and session_token
    final primaryKey = userSessionsTable.keys.firstWhere((k) => k.isPrimary);
    expect(primaryKey.columns, equals(['system_id', 'session_token']));
    
    // Print schema for debugging
    print('Composite key schema built successfully');
    print('Columns: ${userSessionsTable.columns.map((c) => '${c.name}(${c.logicalType})').join(', ')}');
    print('Keys: ${userSessionsTable.keys.map((k) => '${k.columns.join(",")} (${k.type})').join('; ')}');
    
    // Verify we can create a database with this schema
    final database = await DeclarativeDatabase.open(
      ':memory:',
      databaseFactory: databaseFactoryFfi,
      schema: schema,
      fileRepository: FilesystemFileRepository('temp_test'),
    );
    
    // Insert multiple records to test composite key behavior
    final systemId1 = await database.insert('user_sessions', {
      'session_token': 'token1',
      'created_at': '2024-01-01T00:00:00.000Z',
    });
    
    final systemId2 = await database.insert('user_sessions', {
      'session_token': 'token2', // Different token, same system_id is allowed
      'created_at': '2024-01-01T01:00:00.000Z',
    });
    
    // Verify both records exist
    final results = await database.queryTable('user_sessions');
    expect(results.length, equals(2));
    
    // Both should have different system_ids 
    expect(systemId1, isNot(equals(systemId2)));
    
    await database.close();
  });

  test('should allow other types of keys on system columns', () async {
    sqfliteFfiInit();
    
    final schemaBuilder = SchemaBuilder();
    
    // Test index and unique constraints on system columns
    schemaBuilder.table('audit_log', (table) {
      table.text('action').notNull('');
      table.text('details').notNull('');
      // Regular primary key on user column
      table.key(['action']).primary();
      // Index on system_created_at for performance
      table.key(['system_created_at']).index();
      // Unique constraint on system_version (just for testing)
      table.key(['system_version']).unique();
    });
    
    final schema = schemaBuilder.build();
    
    final auditLogTable = schema.tables.firstWhere((t) => t.name == 'audit_log');
    
    // Check all keys are defined correctly
    final primaryKey = auditLogTable.keys.firstWhere((k) => k.isPrimary);
    expect(primaryKey.columns, equals(['action']));
    
    final indexKey = auditLogTable.keys.firstWhere((k) => k.type.toString() == 'KeyType.indexed');
    expect(indexKey.columns, equals(['system_created_at']));
    
    final uniqueKey = auditLogTable.keys.firstWhere((k) => k.isUnique);
    expect(uniqueKey.columns, equals(['system_version']));
    
    print('Multiple key types on system columns work');
    print('Keys: ${auditLogTable.keys.map((k) => '${k.columns.join(",")} (${k.type})').join('; ')}');
    
    // Verify database creation works
    final database = await DeclarativeDatabase.open(
      ':memory:',
      databaseFactory: databaseFactoryFfi,
      schema: schema,
      fileRepository: FilesystemFileRepository('temp_test'),
    );

    await database.close();
  });
}