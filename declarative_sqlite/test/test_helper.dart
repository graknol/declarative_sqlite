import 'package:sqflite_common/sqlite_api.dart';

Future<void> clearDatabase(DatabaseExecutor db) async {
  final tables = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: "type = 'table'",
  );
  final tableNames = tables
      .map((t) => t['name'] as String?)
      .where((n) => n != null)
      .cast<String>();

  for (final tableName in tableNames) {
    if (!tableName.startsWith('sqlite_') &&
        (!tableName.startsWith('__') || tableName == '__dirty_rows')) {
      await db.execute('DELETE FROM $tableName');
    }
  }
}
