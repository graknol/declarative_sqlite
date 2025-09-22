import 'package:declarative_sqlite/src/database.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';

import 'dirty_row.dart';

/// Callback for fetching all data from the server.
/// 
/// The [tableTimestamps] map contains the latest server HLC timestamp
/// for each table that this client has received. The server should return
/// all records that have a server timestamp newer than these values.
typedef OnFetch = Future<void> Function(
    DeclarativeDatabase database, Map<String, Hlc?> tableTimestamps);

typedef OnSend = Future<bool> Function(List<DirtyRow> operations);

/// Manages server synchronization without internal timers.
/// 
/// Timer responsibility has been moved to TaskScheduler for better
/// resource management and fair scheduling.
class ServerSyncManager {
  final DeclarativeDatabase _db;
  final OnFetch onFetch;
  final OnSend onSend;
  final dynamic retryStrategy;

  bool _isSyncing = false;

  ServerSyncManager({
    required DeclarativeDatabase db,
    required this.onFetch,
    required this.onSend,
    this.retryStrategy,
  }) : _db = db;

  /// Performs a complete sync cycle.
  /// 
  /// This should be called by the TaskScheduler at regular intervals.
  Future<void> performSync() async {
    if (_isSyncing) {
      return;
    }
    _isSyncing = true;

    try {
      // 1. Send pending operations
      final pendingOperations = await _db.dirtyRowStore.getAll();
      if (pendingOperations.isNotEmpty) {
        final success = await onSend(pendingOperations);
        if (success) {
          await _db.dirtyRowStore.remove(pendingOperations);
        }
      }

      // 2. Fetch new data from the server with delta timestamps
      final tableTimestamps = await _getTableTimestamps();
      await onFetch(_db, tableTimestamps);
    } catch (e) {
      // Handle errors, potentially using the retryStrategy
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// Gets the latest server timestamp for each table to enable delta sync.
  Future<Map<String, Hlc?>> _getTableTimestamps() async {
    final timestamps = <String, Hlc?>{};
    
    try {
      // Get the latest server timestamp for each table
      for (final table in _db.schema.userTables) {
        final result = await _db.queryTable(
          'sync_server_timestamps',
          columns: ['server_timestamp'],
          where: 'table_name = ?',
          whereArgs: [table.name],
          limit: 1,
        );
        
        if (result.isNotEmpty) {
          final timestampStr = result.first['server_timestamp'] as String?;
          timestamps[table.name] = timestampStr != null ? Hlc.parse(timestampStr) : null;
        } else {
          timestamps[table.name] = null;
        }
      }
    } catch (e) {
      // If sync_server_timestamps table doesn't exist yet, return null timestamps
      for (final table in _db.schema.userTables) {
        timestamps[table.name] = null;
      }
    }
    
    return timestamps;
  }

  /// Updates the server timestamp for a table after successful fetch.
  /// 
  /// This should be called after processing records from the server
  /// to track the latest server timestamp received.
  Future<void> updateTableTimestamp(String tableName, Hlc serverTimestamp) async {
    await _ensureTimestampTableExists();
    
    await _db.upsert(
      'sync_server_timestamps',
      {
        'table_name': tableName,
        'server_timestamp': serverTimestamp.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictFields: ['table_name'],
    );
  }

  /// Ensures the sync_server_timestamps table exists.
  Future<void> _ensureTimestampTableExists() async {
    try {
      await _db.execute('''
        CREATE TABLE IF NOT EXISTS sync_server_timestamps (
          table_name TEXT PRIMARY KEY,
          server_timestamp TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    } catch (e) {
      // Table might already exist
    }
  }

  /// Manually triggers a sync cycle.
  /// 
  /// Deprecated: Use TaskScheduler.triggerTask() instead for better resource management.
  @Deprecated('Use TaskScheduler for triggering sync operations')
  Future<void> triggerSync() => performSync();
}
