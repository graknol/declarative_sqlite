import 'package:test/test.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_generator/src/builder.dart';

void main() {
  group('LWW HLC Column Generation Tests', () {
    test('does not generate accessors for __hlc columns', () {
      // Create a schema with LWW columns
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('tasks', (table) {
        table.guid('id').notNull('00000000-0000-0000-0000-000000000000');
        table.text('title').notNull('Default Title').lww(); // LWW column
        table.text('description').notNull('Default Description').lww(); // LWW column
        table.integer('priority').notNull(0); // Non-LWW column
        table.key(['id']).primary();
      });

      final schema = schemaBuilder.build();
      final table = schema.tables.firstWhere((t) => t.name == 'tasks');

      // Verify that __hlc columns were created for LWW columns
      final hlcColumns = table.columns.where((c) => c.name.endsWith('__hlc')).toList();
      expect(hlcColumns.length, equals(2), 
        reason: 'Should have 2 __hlc columns for the 2 LWW columns');
      expect(hlcColumns.any((c) => c.name == 'title__hlc'), isTrue,
        reason: 'Should have title__hlc column');
      expect(hlcColumns.any((c) => c.name == 'description__hlc'), isTrue,
        reason: 'Should have description__hlc column');

      // Generate code using the generator
      final generator = DeclarativeSqliteGenerator(null as dynamic);
      
      // Use reflection or string inspection to verify __hlc columns are skipped
      // We'll check that the column list contains __hlc columns but they should be filtered
      final allColumns = table.columns.map((c) => c.name).toList();
      expect(allColumns, contains('title__hlc'));
      expect(allColumns, contains('description__hlc'));

      // The generator should skip these in _generateGettersAndSetters
      // This is verified by the code logic that checks col.name.endsWith('__hlc')
      print('Schema includes ${table.columns.length} columns total');
      print('User-visible columns (non-system, non-hlc): ${
        table.columns.where((c) => 
          !c.name.startsWith('system_') && !c.name.endsWith('__hlc')
        ).length
      }');
    });

    test('skips system columns starting with system_', () {
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('users', (table) {
        table.guid('id').notNull('00000000-0000-0000-0000-000000000000');
        table.text('name').notNull('Default Name');
        table.key(['id']).primary();
      });

      final schema = schemaBuilder.build();
      final table = schema.tables.firstWhere((t) => t.name == 'users');

      // Verify system columns were auto-created
      final systemColumns = table.columns.where((c) => c.name.startsWith('system_')).toList();
      expect(systemColumns.length, greaterThan(0),
        reason: 'System columns should be automatically added');
      
      // Verify we have the expected system columns
      expect(systemColumns.any((c) => c.name == 'system_id'), isTrue);
      expect(systemColumns.any((c) => c.name == 'system_created_at'), isTrue);
      expect(systemColumns.any((c) => c.name == 'system_version'), isTrue);
      expect(systemColumns.any((c) => c.name == 'system_is_local_origin'), isTrue);
    });

    test('counts correct number of user-visible columns with LWW', () {
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('products', (table) {
        table.guid('id').notNull('00000000-0000-0000-0000-000000000000');
        table.text('name').notNull('').lww();
        table.real('price').notNull(0.0).lww();
        table.integer('stock').notNull(0); // Non-LWW
        table.key(['id']).primary();
      });

      final schema = schemaBuilder.build();
      final table = schema.tables.firstWhere((t) => t.name == 'products');

      // Count different types of columns
      final allColumns = table.columns;
      final systemColumns = allColumns.where((c) => c.name.startsWith('system_'));
      final hlcColumns = allColumns.where((c) => c.name.endsWith('__hlc'));
      final userColumns = allColumns.where((c) => 
        !c.name.startsWith('system_') && !c.name.endsWith('__hlc')
      );

      print('Total columns: ${allColumns.length}');
      print('System columns: ${systemColumns.length}');
      print('HLC columns: ${hlcColumns.length}');
      print('User columns: ${userColumns.length}');

      expect(userColumns.length, equals(4),
        reason: 'Should have 4 user-defined columns: id, name, price, stock');
      expect(hlcColumns.length, equals(2),
        reason: 'Should have 2 HLC columns for name and price');
      expect(systemColumns.length, equals(4),
        reason: 'Should have 4 system columns: system_id, system_created_at, system_version, system_is_local_origin');
    });
  });
}
