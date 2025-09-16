import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'in_memory_file_repository.dart';
import 'test_helper.dart';

void main() {
  sqfliteFfiInit();

  late DeclarativeDatabase db;
  late ServerSyncManager syncManager;
  late DirtyRowStore operationStore;
  late sqflite.DatabaseFactory databaseFactory;

  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;

    final schemaBuilder = SchemaBuilder();
    schemaBuilder.table('users', (table) {
      table.guid('id').notNull(Uuid().v4());
      table.text('name').notNull('');
      table.key(['id']).primary();
    });
    final schema = schemaBuilder.build();
    operationStore = SqliteDirtyRowStore();

    // 2. Open the database (which also runs migrations)
    db = await DeclarativeDatabase.open(
      inMemoryDatabasePath,
      databaseFactory: databaseFactory,
      schema: schema,
      dirtyRowStore: operationStore,
      fileRepository: InMemoryFileRepository(),
    );
  });

  setUp(() async {
    await clearDatabase(db.db);
  });

  tearDownAll(() async {
    await db.close();
  });

  test('Insert operation is logged', () async {
    final systemId = await db.insert('users', {'id': '1', 'name': 'Alice'});
    final ops = await db.dirtyRowStore.getAll();
    expect(ops.length, 1);
    expect(ops.first.tableName, 'users');
    expect(ops.first.rowId, systemId);
  });

  test('bulkLoad does not log operations', () async {
    // First, insert a record that will be updated
    await db.insert('users', {'id': '1', 'name': 'Alice'});
    // Check that the initial insert was logged
    var ops = await db.dirtyRowStore.getAll();
    expect(ops.length, 1);

    // Now, bulk load data, which includes an update and a new record
    await db.bulkLoad('users', [
      {'id': '2', 'name': 'Bob'}
    ]);

    // Verify that bulkLoad did not add new operations
    ops = await db.dirtyRowStore.getAll();
    expect(ops.length, 1); // Should still be the original insert operation

    // Verify the data was correctly inserted
    final results = await db.queryTable('users', where: "id = '2'");
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
