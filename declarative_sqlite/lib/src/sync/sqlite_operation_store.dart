import 'dart:convert';

import 'package:declarative_sqlite/src/sync/operation.dart';
import 'package:declarative_sqlite/src/sync/operation_store.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;

/// An implementation of [OperationStore] that uses a SQLite table.
class SqliteOperationStore implements OperationStore {
  late final sqflite.DatabaseExecutor _db;
  final String _tableName = '__operations';

  SqliteOperationStore();

  @override
  Future<void> init(sqflite.DatabaseExecutor db) async {
    _db = db;
    await _db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          tableName TEXT NOT NULL,
          rowId TEXT NOT NULL,
          data TEXT,
          timestamp TEXT NOT NULL
        )
      ''');
  }

  @override
  Future<void> add(Operation operation) async {
    await _db.insert(_tableName, {
      'type': operation.type.toString().split('.').last,
      'tableName': operation.tableName,
      'rowId': operation.rowId,
      'data': operation.data != null ? jsonEncode(operation.data) : null,
      'timestamp': operation.timestamp.toIso8601String(),
    });
  }

  @override
  Future<List<Operation>> getAll() async {
    final results = await _db.query(_tableName);
    return results.map((row) {
      final type = OperationType.values
          .firstWhere((e) => e.toString().split('.').last == row['type']);
      return Operation(
        id: row['id'] as int,
        type: type,
        tableName: row['tableName'] as String,
        rowId: row['rowId'] as String,
        data: row['data'] != null ? jsonDecode(row['data'] as String) : null,
        timestamp: DateTime.parse(row['timestamp'] as String),
      );
    }).toList();
  }

  @override
  Future<void> remove(List<Operation> operations) async {
    if (operations.isEmpty) {
      return;
    }
    final ids = operations.map((op) => op.id).toList();
    await _db.delete(
      _tableName,
      where: 'id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
    );
  }
}
