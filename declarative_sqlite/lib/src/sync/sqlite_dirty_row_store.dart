import 'dart:async';
import 'dart:convert';

import 'package:declarative_sqlite/src/sync/dirty_row.dart';
import 'package:declarative_sqlite/src/sync/dirty_row_store.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:sqflite_common/sqflite.dart';

/// An implementation of [DirtyRowStore] that uses a SQLite table.
class SqliteDirtyRowStore implements DirtyRowStore {
  late final DatabaseExecutor _db;
  final String _tableName = '__dirty_rows';
  
  /// Stream controller for broadcasting when dirty rows are added
  final StreamController<DirtyRow> _rowAddedController = StreamController<DirtyRow>.broadcast();

  SqliteDirtyRowStore();

  @override
  Future<void> init(DatabaseExecutor db) async {
    _db = db;
  }

  @override
  Future<void> add(String tableName, String rowId, Hlc hlc, bool isFullRow, [Map<String, Object?>? data]) async {
    // Serialize data to JSON if provided
    String? dataJson;
    if (data != null) {
      dataJson = jsonEncode(data);
    }
    
    await _db.rawInsert('''
      INSERT OR REPLACE INTO $_tableName (table_name, row_id, hlc, is_full_row, data)
      VALUES (?, ?, ?, ?, ?)
    ''', [tableName, rowId, hlc.toString(), isFullRow ? 1 : 0, dataJson]);
    
    // Emit the dirty row to the stream
    final dirtyRow = DirtyRow(
      tableName: tableName,
      rowId: rowId,
      hlc: hlc,
      isFullRow: isFullRow,
      data: data,
    );
    _rowAddedController.add(dirtyRow);
  }

  @override
  Stream<DirtyRow> get onRowAdded => _rowAddedController.stream;

  @override
  Future<List<DirtyRow>> getAll() async {
    final results = await _db.query(
      _tableName,
      columns: ['table_name', 'row_id', 'hlc', 'is_full_row', 'data'],
    );
    return results.map((row) {
      final dataJson = row['data'] as String?;
      Map<String, Object?>? data;
      if (dataJson != null) {
        try {
          final decoded = jsonDecode(dataJson);
          if (decoded is Map) {
            data = decoded.cast<String, Object?>();
          }
        } catch (e) {
          // If JSON parsing fails, leave data as null
          data = null;
        }
      }
      
      return DirtyRow(
        tableName: row['table_name'] as String,
        rowId: row['row_id'] as String,
        hlc: Hlc.parse(row['hlc'] as String),
        isFullRow: (row['is_full_row'] as int) == 1,
        data: data,
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
      // We don't need to match on data, just the key fields
      await _db.delete(
        _tableName,
        where: 'table_name = ? AND row_id = ? AND hlc = ? AND is_full_row = ?',
        whereArgs: [
          operation.tableName,
          operation.rowId,
          operation.hlc.toString(),
          operation.isFullRow ? 1 : 0,
        ],
      );
    }
  }

  @override
  Future<void> clear() async {
    await _db.delete(_tableName);
  }

  @override
  Future<void> dispose() async {
    await _rowAddedController.close();
  }
}
