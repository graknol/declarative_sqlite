import 'package:sqflite_common/sqflite.dart' as sqflite;
import 'package:declarative_sqlite/src/schema/live_schema.dart';

Future<LiveSchema> introspectSchema(sqflite.Database db) async {
  final tables = await _introspectTables(db);
  final views = await _introspectViews(db);
  return LiveSchema(tables: tables, views: views);
}

Future<List<LiveTable>> _introspectTables(sqflite.Database db) async {
  final tables = <LiveTable>[];
  final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_metadata'");
  for (final tableRow in tableRows) {
    final tableName = tableRow['name'] as String;
    final columns = await _introspectColumns(db, tableName);
    final keys = await _introspectKeys(db, tableName);
    tables.add(LiveTable(name: tableName, columns: columns, keys: keys));
  }
  return tables;
}

Future<List<LiveView>> _introspectViews(sqflite.Database db) async {
  final views = <LiveView>[];
  final viewRows = await db
      .rawQuery("SELECT name, sql FROM sqlite_master WHERE type='view'");
  for (final viewRow in viewRows) {
    views.add(LiveView(
      name: viewRow['name'] as String,
      sql: viewRow['sql'] as String,
    ));
  }
  return views;
}

Future<List<LiveColumn>> _introspectColumns(
    sqflite.Database db, String tableName) async {
  final columns = <LiveColumn>[];
  final columnRows = await db.rawQuery('PRAGMA table_info($tableName)');
  for (final columnRow in columnRows) {
    columns.add(LiveColumn(
      name: columnRow['name'] as String,
      type: columnRow['type'] as String,
      isNotNull: (columnRow['notnull'] as int) == 1,
      isPrimaryKey: (columnRow['pk'] as int) >= 1,
      defaultValue: columnRow['dflt_value'] as String?,
    ));
  }
  return columns;
}

Future<List<LiveKey>> _introspectKeys(
    sqflite.Database db, String tableName) async {
  final keys = <LiveKey>[];
  final indexList = await db.rawQuery('PRAGMA index_list($tableName)');
  for (final indexRow in indexList) {
    final indexName = indexRow['name'] as String;
    final isUnique = (indexRow['unique'] as int) == 1;
    final indexInfo = await db.rawQuery('PRAGMA index_info($indexName)');
    final columns = indexInfo.map((row) => row['name'] as String).toList();
    keys.add(LiveKey(name: indexName, columns: columns, isUnique: isUnique));
  }
  return keys;
}
