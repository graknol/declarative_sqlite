import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_helper.dart';

void main() {
  late DeclarativeDatabase db;
  late ServerSyncManager syncManager;

  setUp(() async {
    final schemaBuilder = SchemaBuilder();
    schemaBuilder.table('users', (table) {
      table.guid('id').notNull(Uuid().v4());
      table.text('name').notNull('');
      table.key(['id']).primary();
    });
    final schema = schemaBuilder.build();

    db = await setupTestDatabase(schema: schema);
  });

  tearDown(() async {
    await db.close();
  });

  test('Insert operation is logged', () async {
    final systemId = await db.insert('users', {'id': '1', 'name': 'Alice'});
    final ops = await db.dirtyRowStore.getAll();
    expect(ops.length, 1);
    expect(ops.first.tableName, 'users');
    expect(ops.first.rowId, systemId);
  });

  test('bulkLoad inserts rows', () async {
    // Bulk load data.
    await db.bulkLoad('users', [
      {
        'id': '1',
        'name': 'Alice',
        'system_id': 'f7a3ab6c-69ec-4c16-bc5e-5acd3328fa0b',
      },
      {
        'id': '2',
        'name': 'Bob',
        'system_id': '470ccec6-c583-44b2-942d-a28455b753e2',
      },
    ]);

    // Verify the data was correctly inserted by bulkLoad
    final results = await db.queryTable('users');
    expect(results.length, 2);
  });

  test('bulkLoad does not log operations', () async {
    // First, insert a record. This will be our baseline, creating one dirty row.
    await db.insert('users', {'id': '1', 'name': 'Alice'});
    var ops = await db.dirtyRowStore.getAll();
    expect(ops.length, 1);

    // Now, bulk load a different record. This should NOT create any new dirty rows.
    await db.bulkLoad('users', [
      {
        'id': '2',
        'name': 'Bob',
        'system_id': '744b5978-422b-4c48-a87f-4a6db9e5465d',
      },
    ]);

    // Verify that bulkLoad did not add new operations. The count should still be 1.
    ops = await db.dirtyRowStore.getAll();
    expect(ops.length, 1);

    // Verify the data from bulkLoad was correctly inserted.
    final results =
        await db.queryTable('users', where: "id = ?", whereArgs: ['2']);
    expect(results.length, 1);
    expect(results[0]['name'], 'Bob');
  });

  test('Sync manager sends operations and clears them on success', () async {
    await db.insert('users', {'id': '1', 'name': 'Alice'});

    List<DirtyRow> sentOps = [];
    syncManager = ServerSyncManager(
      db: db,
      onSend: (operations) async {
        sentOps.addAll(operations);
        return true; // Simulate successful send
      },
      onFetch: (dataAccess, tableName, clock) async {
        // Do nothing for this test
      },
      fetchInterval: const Duration(days: 1), // Prevent auto-fetching
    );

    await syncManager.triggerSync();

    expect(sentOps.length, 1);
    final ops = await db.dirtyRowStore.getAll();
    expect(ops.isEmpty, isTrue);
  });
}
