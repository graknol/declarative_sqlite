import 'package:declarative_sqlite/src/sync/dirty_row.dart';
import 'package:declarative_sqlite/src/sync/dirty_row_store.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:sqflite_common/sqflite.dart';

/// An implementation of [DirtyRowStore] that uses a SQLite table.
class SqliteDirtyRowStore implements DirtyRowStore {
  late final DatabaseExecutor _db;
  final String _tableName = '__dirty_rows';

  SqliteDirtyRowStore();

  @override
  Future<void> init(DatabaseExecutor db) async {
    _db = db;
  }

  @override
  Future<void> add(String tableName, String rowId, Hlc hlc) async {
    await _db.rawInsert('''
      INSERT OR REPLACE INTO $_tableName (table_name, row_id, hlc)
      VALUES (?, ?, ?)
    ''', [tableName, rowId, hlc.toString()]);
  }

  @override
  Future<List<DirtyRow>> getAll() async {
    final results = await _db.query(
      _tableName,
      columns: ['table_name', 'row_id', 'hlc'],
    );
    return results.map((row) {
      return DirtyRow(
        tableName: row['table_name'] as String,
        rowId: row['row_id'] as String,
        hlc: Hlc.parse(row['hlc'] as String),
      );
    }).toList();
  }

  /// Removes a list of rows from the dirty rows log.
  ///
  /// This should be called after successfully syncing rows with a server.
  /// It uses a lock-free approach to only remove rows that have not been
  /// modified again since the sync started.
  @override
  Future<void> remove(List<DirtyRow> operations) async {
    for (final operation in operations) {
      await _db.delete(
        _tableName,
        where: 'table_name = ? AND row_id = ? AND hlc = ?',
        whereArgs: [
          operation.tableName,
          operation.rowId,
          operation.hlc.toString()
        ],
      );
    }
  }

  @override
  Future<void> clear() async {
    await _db.delete(_tableName);
  }
}
