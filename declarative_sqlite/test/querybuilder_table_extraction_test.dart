import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('QueryBuilder table extraction', () {
    late Database database;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      database = await openDatabase(':memory:');
    });

    tearDown(() async {
      await database.close();
    });

    test('can extract table name from QueryBuilder', () async {
      // Create a simple schema
      final schema = SchemaBuilder()
        .table('users', (table) => table
            .autoIncrementPrimaryKey('id')
            .text('name', (col) => col.notNull())
            .text('email', (col) => col.unique())
            .integer('age'));

      // Apply schema
      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);

      // Test QueryBuilder with table extraction
      final queryBuilder = QueryBuilder().selectAll().from('users');
      
      // Verify we can extract table name
      expect(queryBuilder.fromTable, equals('users'));
      
      // Test SQL generation
      expect(queryBuilder.toSql(), contains('FROM users'));
      
      // Create data access
      final dataAccess = await DataAccess.create(database: database, schema: schema);
      
      // Insert test data
      await dataAccess.insert('users', {
        'name': 'John Doe',
        'email': 'john@example.com',
        'age': 30
      });
      
      // Execute query
      final result = await queryBuilder.executeMany(dataAccess);
      expect(result, isNotEmpty);
      expect(result.first['name'], equals('John Doe'));
      
      // Test that we can get table schema from the QueryBuilder's fromTable
      final table = schema.tables.firstWhere((t) => t.name == queryBuilder.fromTable);
      expect(table.name, equals('users'));
      expect(table.columns.length, greaterThan(0));
    });
  });
}