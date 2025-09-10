import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('SchemaMigrator Integration Tests', () {
    late Database database;
    late SchemaMigrator migrator;

    setUpAll(() {
      // Initialize sqflite_ffi for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Create an in-memory database for each test
      database = await openDatabase(inMemoryDatabasePath);
      migrator = SchemaMigrator();
    });

    tearDown(() async {
      await database.close();
    });

    test('can create new tables from schema', () async {
      final schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .text('email', (col) => col.unique())
              .integer('age'));

      // Verify schema validation passes
      final validationErrors = migrator.validateSchema(schema);
      expect(validationErrors, isEmpty);

      // Apply migration
      await migrator.migrate(database, schema);

      // Verify table was created
      final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      expect(tables.map((t) => t['name']), contains('users'));

      // Verify table structure
      final columns = await database.rawQuery('PRAGMA table_info(users)');
      expect(columns, hasLength(4));
      
      final columnNames = columns.map((c) => c['name']).toList();
      expect(columnNames, containsAll(['id', 'name', 'email', 'age']));
    });

    test('can create indices during migration', () async {
      final schema = SchemaBuilder()
          .table('posts', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .integer('user_id')
              .index('idx_user_id', 'user_id')
              .compositeIndex('idx_title_user', ['title', 'user_id'], unique: true));

      await migrator.migrate(database, schema);

      // Verify indices were created
      final indices = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'");
      
      final indexNames = indices.map((i) => i['name']).toList();
      expect(indexNames, containsAll(['idx_user_id', 'idx_title_user']));
    });

    test('can create migration plan', () async {
      final schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name')
              .index('idx_name', 'name'));

      final plan = await migrator.planMigration(database, schema);
      
      expect(plan.hasOperations, isTrue);
      expect(plan.tablesToCreate, contains('users'));
      expect(plan.indicesToCreate, contains('idx_name'));
    });

    test('handles existing tables gracefully', () async {
      // First, create a table manually
      await database.execute('CREATE TABLE existing_table (id INTEGER PRIMARY KEY, name TEXT)');

      final schema = SchemaBuilder()
          .table('existing_table', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name')
              .index('new_index', 'name'));

      // Migration should not fail and should add the missing index
      await migrator.migrate(database, schema);

      // Verify the new index was added
      final indices = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='new_index'");
      expect(indices, hasLength(1));
    });

    test('validates schema before migration', () async {
      // Empty schema is valid (just doesn't do anything)
      final emptySchema = SchemaBuilder();
      final errors = migrator.validateSchema(emptySchema);
      expect(errors, isEmpty);
      
      // Test migration with empty schema (should be no-op)
      await migrator.migrate(database, emptySchema);
    });

    test('can insert data after migration', () async {
      final schema = SchemaBuilder()
          .table('test_data', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('message', (col) => col.notNull())
              .integer('value', (col) => col.withDefaultValue(0)));

      await migrator.migrate(database, schema);

      // Insert test data
      await database.insert('test_data', {
        'message': 'Hello, World!',
        'value': 42,
      });

      // Query the data back
      final results = await database.query('test_data');
      expect(results, hasLength(1));
      expect(results.first['message'], equals('Hello, World!'));
      expect(results.first['value'], equals(42));
    });
  });
}