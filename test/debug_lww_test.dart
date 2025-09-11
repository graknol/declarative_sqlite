import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Debug LWW cache issue', () async {
    final database = await openDatabase(':memory:');
    
    final schema = SchemaBuilder()
      .table('tasks', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('title', (col) => col.notNull())
        .integer('hours', (col) => col.lww()));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    final dataAccess = await DataAccess.createWithLWW(
      database: database, 
      schema: schema
    );

    print('LWW enabled: ${dataAccess.lwwEnabled}');
    
    // Insert a regular row first
    final id = await dataAccess.insert('tasks', {
      'title': 'Test Task',
      'hours': 5,
    });
    print('Inserted task with id: $id');

    // Try to update LWW column
    try {
      await dataAccess.updateLWWColumn('tasks', id, 'hours', 8);
      print('Successfully updated LWW column');
    } catch (e, stackTrace) {
      print('Error updating LWW column: $e');
      print('Stack trace: $stackTrace');
    }

    await database.close();
  });
}