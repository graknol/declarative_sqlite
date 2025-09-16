import 'dart:async';

import 'package:declarative_sqlite/src/database.dart';
import 'package:declarative_sqlite/src/sync/sync_types.dart';

class ServerSyncManager {
  final DeclarativeDatabase _db;
  final OnFetch onFetch;
  final OnSend onSend;
  final Duration fetchInterval;
  final dynamic retryStrategy;

  Timer? _fetchTimer;
  bool _isSyncing = false;

  ServerSyncManager({
    required DeclarativeDatabase db,
    required this.onFetch,
    required this.onSend,
    this.fetchInterval = const Duration(minutes: 5),
    this.retryStrategy,
  }) : _db = db;

  void start() {
    _fetchTimer?.cancel();
    _fetchTimer = Timer.periodic(fetchInterval, (_) => _performSync());
    // Perform an initial sync immediately
    _performSync();
  }

  void stop() {
    _fetchTimer?.cancel();
    _fetchTimer = null;
  }

  Future<void> _performSync() async {
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

      // 2. Fetch new data from the server
      for (final table in _db.schema.tables) {
        // In a real implementation, we would manage the clock per table
        await onFetch(_db, table.name, null);
      }
    } catch (e) {
      // Handle errors, potentially using the retryStrategy
    } finally {
      _isSyncing = false;
    }
  }

  /// Manually triggers a sync cycle.
  Future<void> triggerSync() => _performSync();
}
