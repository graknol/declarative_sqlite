import 'package:sqflite_common/sqlite_api.dart';

Future<void> clearDatabase(DatabaseExecutor db) async {
  final tables = await db.query('sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'");

    for (final table in tables) {
      await db.execute('DELETE FROM ${table['name']}');
    }
}
