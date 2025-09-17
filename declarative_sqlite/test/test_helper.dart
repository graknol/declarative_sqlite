import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'in_memory_file_repository.dart';

bool _sqliteFfiInitialized = false;

Future<void> clearDatabase(DatabaseExecutor db) async {
  final tables = await db.query('sqlite_master',
      columns: ['name'], where: 'type = ?', whereArgs: ['table']);
  for (final table in tables) {
    final tableName = table['name'] as String;
    if (!tableName.startsWith('sqlite_')) {
      await db.delete(tableName);
    }
  }
}

Future<DeclarativeDatabase> setupTestDatabase({required Schema schema}) async {
  final dbName = Uuid().v4();
  if (!_sqliteFfiInitialized) {
    sqfliteFfiInit();
    _sqliteFfiInitialized = true;
  }
  return DeclarativeDatabase.open(
    'file:$dbName?mode=memory&cache=shared',
    schema: schema,
    databaseFactory: databaseFactoryFfi,
    fileRepository: InMemoryFileRepository(),
    isSingleInstance: false,
  );
}
