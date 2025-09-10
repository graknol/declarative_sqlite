import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('SchemaMigrator Integration Tests', () {
    late Database database;
    late SchemaMigrator migrator;
    late DataAccess dataAccess;

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
      expect(columns, hasLength(6)); // Now includes systemId and systemVersion
      
      final columnNames = columns.map((c) => c['name']).toList();
      expect(columnNames, containsAll(['systemId', 'systemVersion', 'id', 'name', 'email', 'age']));
    });

    test('can create indices during migration', () async {
      final schema = SchemaBuilder()
          .table('posts', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .integer('user_id')
              .index('idx_user_id', ['user_id'])
              .index('idx_title_user', ['title', 'user_id'], unique: true));

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
              .index('idx_name', ['name']));

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
              .index('new_index', ['name']));

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

      // Create DataAccess for this schema
      dataAccess = DataAccess(database: database, schema: schema);

      // Insert test data using DataAccess
      await dataAccess.insert('test_data', {
        'message': 'Hello, World!',
        'value': 42,
      });

      // Query the data back
      final results = await database.query('test_data');
      expect(results, hasLength(1));
      expect(results.first['message'], equals('Hello, World!'));
      expect(results.first['value'], equals(42));
    });

    test('can add indices to existing table', () async {
      // First, create a table without indices
      final initialSchema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .text('email', (col) => col.unique()));

      await migrator.migrate(database, initialSchema);

      // Create DataAccess for initial schema
      dataAccess = DataAccess(database: database, schema: initialSchema);

      // Insert some initial data using DataAccess
      await dataAccess.insert('users', {'name': 'John Doe', 'email': 'john@example.com'});

      // Now add index to the schema (on existing column)
      final extendedSchema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .text('email', (col) => col.unique())
              .index('idx_name', ['name'])
              .index('idx_email', ['email']));

      // Migrate with the new indices
      await migrator.migrate(database, extendedSchema);

      // Verify the original data still exists
      final results = await database.query('users');
      expect(results, hasLength(1));
      expect(results.first['name'], equals('John Doe'));
      expect(results.first['email'], equals('john@example.com'));

      // Verify the new indices were created
      final indices = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name IN ('idx_name', 'idx_email')");
      expect(indices, hasLength(2));
    });

    test('handles complex schema evolution scenarios', () async {
      // Create initial schema with basic tables
      final v1Schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('username', (col) => col.notNull().unique())
              .text('email', (col) => col.notNull())
              .index('idx_username', ['username']))
          .table('posts', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .integer('user_id', (col) => col.notNull()));

      await migrator.migrate(database, v1Schema);

      // Create DataAccess for v1 schema
      dataAccess = DataAccess(database: database, schema: v1Schema);

      // Add some data to v1 schema using DataAccess
      final userId = await dataAccess.insert('users', {
        'username': 'alice',
        'email': 'alice@example.com',
      });
      await dataAccess.insert('posts', {
        'title': 'My First Post',
        'user_id': userId,
      });

      // Evolve schema - add new table and indices
      final v2Schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('username', (col) => col.notNull().unique())
              .text('email', (col) => col.notNull())
              .index('idx_username', ['username'])
              .index('idx_email', ['email'])) // New index
          .table('posts', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .integer('user_id', (col) => col.notNull())
              .index('idx_user_id', ['user_id'])) // New index
          .table('comments', (table) => table  // New table
              .autoIncrementPrimaryKey('id')
              .text('content', (col) => col.notNull())
              .integer('post_id', (col) => col.notNull())
              .integer('user_id', (col) => col.notNull())
              .index('idx_post_id', ['post_id'])
              .index('idx_user_id_post_id', ['user_id', 'post_id'], unique: true));

      await migrator.migrate(database, v2Schema);

      // Update DataAccess for v2 schema
      dataAccess = DataAccess(database: database, schema: v2Schema);

      // Verify all tables exist
      final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
      final tableNames = tables.map((t) => t['name']).toList();
      expect(tableNames, containsAll(['users', 'posts', 'comments']));

      // Verify new indices were created
      final indices = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' ORDER BY name");
      final indexNames = indices.map((i) => i['name']).toList();
      expect(indexNames, containsAll([
        'idx_username', 'idx_email', 'idx_user_id', 
        'idx_post_id', 'idx_user_id_post_id'
      ]));

      // Verify existing data is preserved
      final userData = await database.query('users');
      expect(userData, hasLength(1));
      expect(userData.first['username'], equals('alice'));

      final postData = await database.query('posts');
      expect(postData, hasLength(1));
      expect(postData.first['title'], equals('My First Post'));

      // Verify new table can accept data using DataAccess
      await dataAccess.insert('comments', {
        'content': 'Great post!',
        'post_id': 1,
        'user_id': 1,
      });

      final commentData = await database.query('comments');
      expect(commentData, hasLength(1));
      expect(commentData.first['content'], equals('Great post!'));
    });

    test('can handle schema modifications with existing data', () async {
      // Create a table and populate it
      final originalSchema = SchemaBuilder()
          .table('products', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .real('price', (col) => col.notNull()));

      await migrator.migrate(database, originalSchema);

      // Create DataAccess for original schema
      dataAccess = DataAccess(database: database, schema: originalSchema);

      // Insert test data using DataAccess
      await dataAccess.insert('products', {'name': 'Widget', 'price': 19.99});
      await dataAccess.insert('products', {'name': 'Gadget', 'price': 29.99});

      // Modify schema to add indices and validate data preservation
      final updatedSchema = SchemaBuilder()
          .table('products', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .real('price', (col) => col.notNull())
              .index('idx_name', ['name'])
              .index('idx_price', ['price']));

      await migrator.migrate(database, updatedSchema);

      // Verify data is preserved after schema update
      final products = await database.query('products', orderBy: 'price');
      expect(products, hasLength(2));
      expect(products[0]['name'], equals('Widget'));
      expect(products[0]['price'], equals(19.99));
      expect(products[1]['name'], equals('Gadget'));
      expect(products[1]['price'], equals(29.99));

      // Verify indices were created and are functional
      final indices = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name IN ('idx_name', 'idx_price')");
      expect(indices, hasLength(2));
    });
  });
}