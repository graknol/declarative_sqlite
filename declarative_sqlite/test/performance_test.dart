import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'in_memory_file_repository.dart';

void main() {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  group('Performance Tests', () {
    test('Schema migration performance', () async {
      final initialSchemaBuilder = SchemaBuilder();
      initialSchemaBuilder.table('users', (table) {
        table.guid('id').notNull('some_default_id');
        table.text('name').notNull('Default Name');
        table.integer('age').notNull(0);
        table.key(['id']).primary();
      });
      final initialSchema = initialSchemaBuilder.build();

      // Initial creation
      var db = await DeclarativeDatabase.open(
        inMemoryDatabasePath,
        databaseFactory: databaseFactory,
        schema: initialSchema,
        operationStore: MockOperationStore(),
        fileRepository: InMemoryFileRepository(),
      );

      // Insert some data to make the migration more realistic
      await db.dataAccess.bulkLoad(
          'users',
          List.generate(
              100, (i) => {'id': Uuid().v4(), 'name': 'User $i', 'age': i}));
      await db.close();

      final migratedSchemaBuilder = SchemaBuilder();
      migratedSchemaBuilder.table('users', (table) {
        table.guid('id').notNull('some_default_id');
        table.text('name').notNull('Default Name');
        table.integer('age').notNull(0);
        table.text('email').notNull('default@email.com'); // Add column
        table.key(['id']).primary();
        table.key(['name']).index(); // Add index
      });
      final migratedSchema = migratedSchemaBuilder.build();

      final stopwatch = Stopwatch()..start();
      // This will trigger the migration
      db = await DeclarativeDatabase.open(
        inMemoryDatabasePath,
        databaseFactory: databaseFactory,
        schema: migratedSchema,
        operationStore: MockOperationStore(),
        fileRepository: InMemoryFileRepository(),
      );
      stopwatch.stop();
      print('Schema migration (100 rows): ${stopwatch.elapsedMilliseconds}ms');
      await db.close();
    });

    test('bulkLoad performance', () async {
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('items', (table) {
        table.integer('id').notNull(0);
        table.text('name').notNull('');
        table.key(['id']).primary();
      });
      final schema = schemaBuilder.build();

      final db = await DeclarativeDatabase.open(
        inMemoryDatabasePath,
        databaseFactory: databaseFactory,
        schema: schema,
        operationStore: MockOperationStore(),
        fileRepository: InMemoryFileRepository(),
      );

      final items = List.generate(1000, (i) => {'id': i, 'name': 'Item $i'});

      final stopwatch = Stopwatch()..start();
      await db.dataAccess.bulkLoad('items', items);
      stopwatch.stop();
      print('bulkLoad (1000 items): ${stopwatch.elapsedMilliseconds}ms');

      await db.close();
    });

    test('Data query performance', () async {
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('items', (table) {
        table.integer('id').notNull(0);
        table.text('name').notNull('');
        table.key(['id']).primary();
      });
      final schema = schemaBuilder.build();

      final db = await DeclarativeDatabase.open(
        inMemoryDatabasePath,
        databaseFactory: databaseFactory,
        schema: schema,
        operationStore: MockOperationStore(),
        fileRepository: InMemoryFileRepository(),
      );

      final items = List.generate(1000, (i) => {'id': i, 'name': 'Item $i'});
      await db.dataAccess.bulkLoad('items', items);

      final stopwatch = Stopwatch()..start();
      await db.queryWith(QueryBuilder().from('items'));
      stopwatch.stop();
      print('Query (1000 items): ${stopwatch.elapsedMilliseconds}ms');

      await db.close();
    });

    test('Data update performance', () async {
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('items', (table) {
        table.integer('id').notNull(0);
        table.text('name').notNull('');
        table.key(['id']).primary();
      });
      final schema = schemaBuilder.build();

      final db = await DeclarativeDatabase.open(
        inMemoryDatabasePath,
        databaseFactory: databaseFactory,
        schema: schema,
        operationStore: MockOperationStore(),
        fileRepository: InMemoryFileRepository(),
      );

      final items = List.generate(1000, (i) => {'id': i, 'name': 'Item $i'});
      await db.dataAccess.bulkLoad('items', items);

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        await db.update(
          'items',
          {'name': 'Updated Item $i'},
          where: 'id = ?',
          whereArgs: [i],
        );
      }
      stopwatch.stop();
      print('Update (1000 items): ${stopwatch.elapsedMilliseconds}ms');

      await db.close();
    });
  });
}

class MockOperationStore implements OperationStore {
  @override
  Future<void> add(Operation operation) async {}

  @override
  Future<List<Operation>> getAll() async => [];

  @override
  Future<void> init(dynamic db) async {}

  @override
  Future<void> remove(List<Operation> operations) async {}
}
