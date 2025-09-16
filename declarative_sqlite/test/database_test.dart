import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'mock_operation_store.dart';

void main() {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  test('Database query method executes and returns correct data', () async {
    // 1. Define a schema
    final schemaBuilder = SchemaBuilder()..version(1);
    schemaBuilder.table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.integer('age').notNull(0);
      table.key(['id']).primary();
    });
    final schema = schemaBuilder.build();

    // 2. Open the database (which also runs migrations)
    final db = await DeclarativeDatabase.open(
      inMemoryDatabasePath,
      schema: schema,
      databaseFactory: databaseFactory,
      operationStore: MockOperationStore(),
    );

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

  test('LWW columns update correctly', () async {
    // 1. Define a schema with an LWW column
    final schemaBuilder = SchemaBuilder()..version(1);
    schemaBuilder.table('products', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('').lww(); // name is an LWW column
      table.integer('stock').notNull(0); // stock is a regular column
      table.key(['id']).primary();
    });
    final schema = schemaBuilder.build();

    // 2. Open the database
    final db = await DeclarativeDatabase.open(
      inMemoryDatabasePath,
      schema: schema,
      databaseFactory: databaseFactory,
      operationStore: MockOperationStore(),
    );

    // 3. Insert a product
    await db.insert('products', {'id': 1, 'name': 'Original', 'stock': 10});

    // 4. Verify initial state
    var product = (await db.queryTable('products', where: 'id = 1')).first;
    expect(product['name'], 'Original');
    expect(product['stock'], 10);
    expect(product['name__hlc'], isNotNull);
    final initialHlc = Hlc.fromString(product['name__hlc'] as String);

    // 5. Update the LWW column and a regular column
    await db.update(
      'products',
      {'name': 'First Update', 'stock': 20},
      where: 'id = ?',
      whereArgs: [1],
    );

    // 6. Verify the update was successful
    product = (await db.queryTable('products', where: 'id = 1')).first;
    expect(product['name'], 'First Update');
    expect(product['stock'], 20);
    final firstUpdateHlc = Hlc.fromString(product['name__hlc'] as String);
    expect(firstUpdateHlc.compareTo(initialHlc), greaterThan(0));

    // 7. Manually craft an update with an older HLC for the LWW column
    // This simulates a conflict where an older write arrives after a newer one.
    // The LWW 'name' field should NOT be updated, but the regular 'stock'
    // field should be.
    final staleHlc = Hlc(0, 0, 'stale_node');

    // The scenario to test is when a sync message arrives with data. That
    // data would be applied via `bulkLoad` or a similar method that respects
    // incoming HLCs. `bulkLoad` uses `insert` with `replace`.
    // Let's test that flow.

    // Simulate an incoming record with a stale HLC for 'name'
    final staleData = {
      'id': 1,
      'name': 'Stale Update',
      'name__hlc': staleHlc.toString(),
      'stock': 30,
    };

    await db.dataAccess.bulkLoad('products', [staleData]);

    // 8. Verify that the LWW column was NOT updated, but the other was.
    product = (await db.queryTable('products', where: 'id = 1')).first;
    expect(product['name'], 'First Update'); // Should not have changed
    expect(product['stock'], 30); // Regular columns are always updated
    final finalHlc = Hlc.fromString(product['name__hlc'] as String);
    expect(finalHlc, firstUpdateHlc); // HLC should not have changed

    await db.close();
  });
}
