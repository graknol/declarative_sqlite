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
    try {
      final affectedQueries = _activeQueries.values
          .where((query) => query.isActive && query.isAffectedByTable(tableName))
          .toList();

      if (affectedQueries.isEmpty) return;

      // Refresh all affected queries concurrently with error handling
      final results = await Future.wait(
        affectedQueries.map((query) async {
          try {
            await query.refresh();
            return null;
          } catch (e) {
            // Log the error but don't let one query failure stop others
            return 'Query ${query.id} refresh failed: $e';
          }
        }),
      );

      // Handle any errors that occurred
      final errors = results.where((error) => error != null).toList();
      if (errors.isNotEmpty) {
        // In a production app, you might want to log these errors
        // For now, we just ensure other queries continue to work
      }
    } catch (e) {
      // Ensure that notification failures don't crash the database operations
      rethrow;
    }
  }

  /// Notifies all relevant queries that a specific column has been modified
  Future<void> notifyColumnChanged(String tableName, String columnName) async {
    try {
      final affectedQueries = _activeQueries.values
          .where((query) => 
              query.isActive && 
              query.isAffectedByColumn(tableName, columnName))
          .toList();

      if (affectedQueries.isEmpty) return;

      // Refresh all affected queries concurrently with error handling
      final results = await Future.wait(
        affectedQueries.map((query) async {
          try {
            await query.refresh();
            return null;
          } catch (e) {
            // Log the error but don't let one query failure stop others
            return 'Query ${query.id} refresh failed: $e';
          }
        }),
      );

      // Handle any errors that occurred
      final errors = results.where((error) => error != null).toList();
      if (errors.isNotEmpty) {
        // In a production app, you might want to log these errors
        // For now, we just ensure other queries continue to work
      }
    } catch (e) {
      // Ensure that notification failures don't crash the database operations
      rethrow;
    }
  }

  /// Returns the number of active streaming queries
  int get activeQueryCount => _activeQueries.values.where((q) => q.isActive).length;

  /// Returns the total number of registered queries
  int get totalQueryCount => _activeQueries.length;

  /// Notifies all relevant queries about multiple table changes at once
  /// This is more efficient than calling notifyTableChanged multiple times
  Future<void> notifyMultipleTablesChanged(List<String> tableNames) async {
    if (tableNames.isEmpty) return;

    try {
      // Collect all affected queries (deduplicated)
      final affectedQueries = <String, StreamingQuery>{};
      
      for (final tableName in tableNames) {
        for (final query in _activeQueries.values) {
          if (query.isActive && query.isAffectedByTable(tableName)) {
            affectedQueries[query.id] = query;
          }
        }
      }

      if (affectedQueries.isEmpty) return;

      // Refresh all affected queries concurrently
      final results = await Future.wait(
        affectedQueries.values.map((query) async {
          try {
            await query.refresh();
            return null;
          } catch (e) {
            return 'Query ${query.id} refresh failed: $e';
          }
        }),
      );

      // Handle any errors that occurred
      final errors = results.where((error) => error != null).toList();
      if (errors.isNotEmpty) {
        // In a production app, you might want to log these errors
      }
    } catch (e) {
      rethrow;
    }
  }

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