import 'dart:async';
import 'dart:developer' as developer;
import 'streaming_query.dart';

/// Manages multiple streaming queries and coordinates their updates
class QueryStreamManager {
  final Map<String, StreamingQuery> _activeQueries = {};
  
  /// Registers a streaming query with the manager
  void register(StreamingQuery query) {
    developer.log('QueryStreamManager.register: Registering query id="${query.id}", total queries will be ${_activeQueries.length + 1}', name: 'QueryStreamManager');
    _activeQueries[query.id] = query;
    developer.log('QueryStreamManager.register: Successfully registered query id="${query.id}"', name: 'QueryStreamManager');
  }

  /// Unregisters a streaming query from the manager
  void unregister(String queryId) {
    developer.log('QueryStreamManager.unregister: Unregistering query id="$queryId"', name: 'QueryStreamManager');
    final query = _activeQueries.remove(queryId);
    if (query != null) {
      query.dispose();
      developer.log('QueryStreamManager.unregister: Successfully unregistered and disposed query id="$queryId"', name: 'QueryStreamManager');
    } else {
      developer.log('QueryStreamManager.unregister: Query id="$queryId" was not found in active queries', name: 'QueryStreamManager');
    }
  }

  /// Notifies all relevant queries that a table has been modified
  Future<void> notifyTableChanged(String tableName) async {
    developer.log('QueryStreamManager.notifyTableChanged: Notifying queries about table="$tableName" change, checking ${_activeQueries.length} registered queries', name: 'QueryStreamManager');
    
    try {
      final affectedQueries = _activeQueries.values
          .where((query) => query.isActive && query.isAffectedByTable(tableName))
          .toList();

      developer.log('QueryStreamManager.notifyTableChanged: Found ${affectedQueries.length} affected queries for table="$tableName"', name: 'QueryStreamManager');
      
      if (affectedQueries.isEmpty) {
        developer.log('QueryStreamManager.notifyTableChanged: No affected queries for table="$tableName", skipping refresh', name: 'QueryStreamManager');
        return;
      }

      developer.log('QueryStreamManager.notifyTableChanged: Refreshing ${affectedQueries.length} queries for table="$tableName"', name: 'QueryStreamManager');
      
      // Refresh all affected queries concurrently with error handling
      final results = await Future.wait(
        affectedQueries.map((query) async {
          try {
            developer.log('QueryStreamManager.notifyTableChanged: Refreshing query id="${query.id}" for table="$tableName"', name: 'QueryStreamManager');
            await query.refresh();
            developer.log('QueryStreamManager.notifyTableChanged: Successfully refreshed query id="${query.id}" for table="$tableName"', name: 'QueryStreamManager');
            return null;
          } catch (e) {
            final errorMsg = 'Query ${query.id} refresh failed: $e';
            developer.log('QueryStreamManager.notifyTableChanged: $errorMsg', name: 'QueryStreamManager');
            return errorMsg;
          }
        }),
      );

      // Handle any errors that occurred
      final errors = results.where((error) => error != null).toList();
      if (errors.isNotEmpty) {
        developer.log('QueryStreamManager.notifyTableChanged: ${errors.length} queries had errors during refresh for table="$tableName": ${errors.join(", ")}', name: 'QueryStreamManager');
      } else {
        developer.log('QueryStreamManager.notifyTableChanged: All queries refreshed successfully for table="$tableName"', name: 'QueryStreamManager');
      }
    } catch (e, stackTrace) {
      developer.log('QueryStreamManager.notifyTableChanged: Error during table change notification for table="$tableName"', error: e, stackTrace: stackTrace, name: 'QueryStreamManager');
      rethrow;
    }
  }

  /// Notifies all relevant queries that a specific column has been modified
  Future<void> notifyColumnChanged(String tableName, String columnName) async {
    developer.log('QueryStreamManager.notifyColumnChanged: Notifying queries about column="$tableName.$columnName" change, checking ${_activeQueries.length} registered queries', name: 'QueryStreamManager');
    
    try {
      final affectedQueries = _activeQueries.values
          .where((query) => 
              query.isActive && 
              query.isAffectedByColumn(tableName, columnName))
          .toList();

      developer.log('QueryStreamManager.notifyColumnChanged: Found ${affectedQueries.length} affected queries for column="$tableName.$columnName"', name: 'QueryStreamManager');
      
      if (affectedQueries.isEmpty) {
        developer.log('QueryStreamManager.notifyColumnChanged: No affected queries for column="$tableName.$columnName", skipping refresh', name: 'QueryStreamManager');
        return;
      }

      developer.log('QueryStreamManager.notifyColumnChanged: Refreshing ${affectedQueries.length} queries for column="$tableName.$columnName"', name: 'QueryStreamManager');
      
      // Refresh all affected queries concurrently with error handling
      final results = await Future.wait(
        affectedQueries.map((query) async {
          try {
            developer.log('QueryStreamManager.notifyColumnChanged: Refreshing query id="${query.id}" for column="$tableName.$columnName"', name: 'QueryStreamManager');
            await query.refresh();
            developer.log('QueryStreamManager.notifyColumnChanged: Successfully refreshed query id="${query.id}" for column="$tableName.$columnName"', name: 'QueryStreamManager');
            return null;
          } catch (e) {
            final errorMsg = 'Query ${query.id} refresh failed: $e';
            developer.log('QueryStreamManager.notifyColumnChanged: $errorMsg', name: 'QueryStreamManager');
            return errorMsg;
          }
        }),
      );

      // Handle any errors that occurred
      final errors = results.where((error) => error != null).toList();
      if (errors.isNotEmpty) {
        developer.log('QueryStreamManager.notifyColumnChanged: ${errors.length} queries had errors during refresh for column="$tableName.$columnName": ${errors.join(", ")}', name: 'QueryStreamManager');
      } else {
        developer.log('QueryStreamManager.notifyColumnChanged: All queries refreshed successfully for column="$tableName.$columnName"', name: 'QueryStreamManager');
      }
    } catch (e, stackTrace) {
      developer.log('QueryStreamManager.notifyColumnChanged: Error during column change notification for column="$tableName.$columnName"', error: e, stackTrace: stackTrace, name: 'QueryStreamManager');
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
    developer.log('QueryStreamManager.cleanup: Starting cleanup, checking ${_activeQueries.length} registered queries', name: 'QueryStreamManager');
    
    final inactiveQueries = _activeQueries.entries
        .where((entry) => !entry.value.isActive)
        .map((entry) => entry.key)
        .toList();

    developer.log('QueryStreamManager.cleanup: Found ${inactiveQueries.length} inactive queries to remove: ${inactiveQueries.join(", ")}', name: 'QueryStreamManager');
    
    for (final queryId in inactiveQueries) {
      unregister(queryId);
    }
    
    developer.log('QueryStreamManager.cleanup: Cleanup completed, ${_activeQueries.length} queries remaining', name: 'QueryStreamManager');
  }

  /// Dispose of all queries and clean up
  void dispose() {
    developer.log('QueryStreamManager.dispose: Disposing ${_activeQueries.length} registered queries', name: 'QueryStreamManager');
    
    for (final query in _activeQueries.values) {
      developer.log('QueryStreamManager.dispose: Disposing query id="${query.id}"', name: 'QueryStreamManager');
      query.dispose();
    }
    
    _activeQueries.clear();
    developer.log('QueryStreamManager.dispose: All queries disposed and cleared', name: 'QueryStreamManager');
  }

  @override
  String toString() {
    return 'QueryStreamManager(active: $activeQueryCount, total: $totalQueryCount)';
  }
}