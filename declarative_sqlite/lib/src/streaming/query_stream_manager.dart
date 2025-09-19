import 'dart:async';
import 'streaming_query.dart';

/// Manages multiple streaming queries and coordinates their updates
class QueryStreamManager {
  final Map<String, StreamingQuery> _activeQueries = {};
  
  /// Registers a streaming query with the manager
  void register(StreamingQuery query) {
    _activeQueries[query.id] = query;
  }

  /// Unregisters a streaming query from the manager
  void unregister(String queryId) {
    final query = _activeQueries.remove(queryId);
    query?.dispose();
  }

  /// Notifies all relevant queries that a table has been modified
  Future<void> notifyTableChanged(String tableName) async {
    final affectedQueries = _activeQueries.values
        .where((query) => query.isActive && query.isAffectedByTable(tableName))
        .toList();

    // Refresh all affected queries concurrently
    await Future.wait(
      affectedQueries.map((query) => query.refresh()),
    );
  }

  /// Notifies all relevant queries that a specific column has been modified
  Future<void> notifyColumnChanged(String tableName, String columnName) async {
    final affectedQueries = _activeQueries.values
        .where((query) => 
            query.isActive && 
            query.isAffectedByColumn(tableName, columnName))
        .toList();

    // Refresh all affected queries concurrently
    await Future.wait(
      affectedQueries.map((query) => query.refresh()),
    );
  }

  /// Returns the number of active streaming queries
  int get activeQueryCount => _activeQueries.values.where((q) => q.isActive).length;

  /// Returns the total number of registered queries
  int get totalQueryCount => _activeQueries.length;

  /// Clean up inactive queries
  void cleanup() {
    final inactiveQueries = _activeQueries.entries
        .where((entry) => !entry.value.isActive)
        .map((entry) => entry.key)
        .toList();

    for (final queryId in inactiveQueries) {
      unregister(queryId);
    }
  }

  /// Dispose of all queries and clean up
  void dispose() {
    for (final query in _activeQueries.values) {
      query.dispose();
    }
    _activeQueries.clear();
  }

  @override
  String toString() {
    return 'QueryStreamManager(active: $activeQueryCount, total: $totalQueryCount)';
  }
}