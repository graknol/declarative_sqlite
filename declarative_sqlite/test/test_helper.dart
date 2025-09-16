import 'package:sqflite_common/sqlite_api.dart';

Future<void> clearDatabase(Database db) async {
  final tables = await db.query('sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'");

  await db.transaction((txn) async {
    for (final table in tables) {
      await txn.execute('DELETE FROM ${table['name']}');
    }
  });
}
