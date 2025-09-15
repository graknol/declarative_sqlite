import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Database query method executes and returns correct data', () async {
    // 1. Define a schema
    final schemaBuilder = SchemaBuilder();
    schemaBuilder.table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.integer('age').notNull(0);
      table.key(['id']).primary();
    });
    final schema = schemaBuilder.build();

    // 2. Open the database (which also runs migrations)
    final db = DeclarativeDatabase(inMemoryDatabasePath, schema);
    await db.open();

    // 3. Insert data using the new insert method
    await db.insert('users', {'id': 1, 'name': 'Alice', 'age': 30});
    await db.insert('users', {'id': 2, 'name': 'Bob', 'age': 25});
    await db.insert('users', {'id': 3, 'name': 'Charlie', 'age': 35});

    // 4. Build a query
    final builder =
        QueryBuilder().from('users').where(col('age').gt(28)).orderBy(['name']);

    // 5. Execute the query
    final results = await db.query(builder);

    // 6. Verify the results
    expect(results.length, 2);
    expect(results[0]['name'], 'Alice');
    expect(results[1]['name'], 'Charlie');

    await db.close();
  });
}
