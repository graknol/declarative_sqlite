import 'dart:async';
import 'dart:developer' as developer;
import 'package:rxdart/rxdart.dart';
import 'streaming_query.dart';
import 'query_emoji_utils.dart';

/// Manages multiple streaming queries and coordinates their updates with batching and debouncing
class QueryStreamManager {
  final Map<String, StreamingQuery> _queries = {};
  
  // Use RxDart for batching table change notifications to prevent rapid refresh cycles
  PublishSubject<String> _tableChangeSubject = PublishSubject<String>();
  late StreamSubscription _tableChangeSubscription;
  
  QueryStreamManager() {
    developer.log('QueryStreamManager: Initializing with batched table change processing (100ms buffer window)', name: 'QueryStreamManager');
    
    // Use buffer with debounce to collect ALL table changes within the time window
    _tableChangeSubscription = _tableChangeSubject
        .bufferTime(const Duration(milliseconds: 50))
        .where((batch) => batch.isNotEmpty) // Only process non-empty batches
        .listen(
          _processBatchedTableChanges,
          onError: (error, stackTrace) {
            developer.log('QueryStreamManager: Error in batched stream processing', error: error, stackTrace: stackTrace, name: 'QueryStreamManager');
          },
        );
        
    developer.log('QueryStreamManager: Batched table change subscription established', name: 'QueryStreamManager');
  }
  
  /// Registers a streaming query with the manager
  void register(StreamingQuery query) {
    final emoji = getAnimalEmoji(query.id);
    developer.log('QueryStreamManager.register: $emoji Registering query id="${query.id}", isActive=${query.isActive}', name: 'QueryStreamManager');
    _queries[query.id] = query;
    developer.log('QueryStreamManager.register: $emoji Successfully registered query id="${query.id}". Total queries: ${_queries.length}', name: 'QueryStreamManager');
  }

  /// Unregisters a streaming query from the manager and disposes it
  void unregister(String queryId) {
    final emoji = getAnimalEmoji(queryId);
    developer.log('QueryStreamManager.unregister: $emoji Unregistering query id="$queryId"', name: 'QueryStreamManager');
    final query = _queries.remove(queryId);
    if (query != null) {
      // Fire and forget the async dispose
      query.dispose().catchError((error) {
        developer.log('QueryStreamManager.unregister: $emoji Error disposing query id="$queryId": $error', name: 'QueryStreamManager');
      });
      developer.log('QueryStreamManager.unregister: $emoji Successfully unregistered and disposed query id="$queryId"', name: 'QueryStreamManager');
    } else {
      developer.log('QueryStreamManager.unregister: $emoji Query id="$queryId" was not found in active queries', name: 'QueryStreamManager');
    }
  }

  /// Unregisters a streaming query from the manager without disposing it
  /// This is used when the query is managing its own disposal
  void unregisterOnly(String queryId) {
    final emoji = getAnimalEmoji(queryId);
    final wasPresent = _queries.containsKey(queryId);
    developer.log('QueryStreamManager.unregisterOnly: $emoji Unregistering query id="$queryId" (without disposal). Was present: $wasPresent', name: 'QueryStreamManager');
    _queries.remove(queryId);
    developer.log('QueryStreamManager.unregisterOnly: $emoji Successfully unregistered query id="$queryId". Total queries: ${_queries.length}', name: 'QueryStreamManager');
  }

  /// Notifies all relevant queries that a table has been modified (batched to prevent rapid cycles)
  Future<void> notifyTableChanged(String tableName) async {
    developer.log('QueryStreamManager.notifyTableChanged: Queuing table change notification for table="$tableName" (will be batched). Currently ${_queries.length} queries registered.', name: 'QueryStreamManager');
    
    // Check if we have any queries that would be affected
    final affectedCount = _queries.values
        .where((query) => query.isActive && query.isAffectedByTable(tableName))
        .length;
    developer.log('QueryStreamManager.notifyTableChanged: $affectedCount queries would be affected by table="$tableName" change', name: 'QueryStreamManager');
    
    // Debug the state of the debouncing stream
    if (_tableChangeSubject.isClosed) {
      developer.log('QueryStreamManager.notifyTableChanged: ERROR - _tableChangeSubject is closed! Resetting debouncing stream and retrying for table="$tableName"', name: 'QueryStreamManager');
      _resetDebouncingStream();
    }
    
    try {
      _tableChangeSubject.add(tableName);
      developer.log('QueryStreamManager.notifyTableChanged: Table change queued for batching, table="$tableName"', name: 'QueryStreamManager');
    } catch (e) {
      developer.log('QueryStreamManager.notifyTableChanged: ERROR adding to _tableChangeSubject for table="$tableName": $e. Attempting to reset stream.', name: 'QueryStreamManager');
      _resetDebouncingStream();
      
      // Try once more after reset
      try {
        _tableChangeSubject.add(tableName);
        developer.log('QueryStreamManager.notifyTableChanged: Successfully queued after stream reset for table="$tableName"', name: 'QueryStreamManager');
      } catch (retryError) {
        developer.log('QueryStreamManager.notifyTableChanged: FATAL - Still failing after stream reset for table="$tableName": $retryError', name: 'QueryStreamManager');
        
        // Last resort: process directly without debouncing
        developer.log('QueryStreamManager.notifyTableChanged: Using fallback direct processing for table="$tableName"', name: 'QueryStreamManager');
        _processTableChange(tableName).catchError((error) {
          developer.log('QueryStreamManager.notifyTableChanged: Fallback processing also failed for table="$tableName": $error', name: 'QueryStreamManager');
        });
      }
    }
  }
  
  /// Process a batch of table change notifications (called after buffering)
  Future<void> _processBatchedTableChanges(List<String> tableNames) async {
    if (tableNames.isEmpty) return;
    
    // Remove duplicates while preserving order
    final uniqueTableNames = tableNames.toSet().toList();
    
    developer.log('QueryStreamManager._processBatchedTableChanges: Processing batched table changes for tables=${uniqueTableNames.join(", ")} (${tableNames.length} events batched into ${uniqueTableNames.length} unique tables), checking ${_queries.length} registered queries', name: 'QueryStreamManager');
    
    try {
      // Collect all affected queries (deduplicated by query ID)
      final affectedQueries = <String, StreamingQuery>{};
      
      for (final tableName in uniqueTableNames) {
        for (final query in _queries.values) {
          if (query.isActive && query.isAffectedByTable(tableName)) {
            affectedQueries[query.id] = query;
          }
        }
      }

      developer.log('QueryStreamManager._processBatchedTableChanges: Found ${affectedQueries.length} unique affected queries for tables=${uniqueTableNames.join(", ")}', name: 'QueryStreamManager');
      
      if (affectedQueries.isEmpty) {
        developer.log('QueryStreamManager._processBatchedTableChanges: No affected queries for tables=${uniqueTableNames.join(", ")}, skipping refresh', name: 'QueryStreamManager');
        return;
      }

      developer.log('QueryStreamManager._processBatchedTableChanges: Refreshing ${affectedQueries.length} queries for tables=${uniqueTableNames.join(", ")}', name: 'QueryStreamManager');
      
      // Refresh all affected queries concurrently with error handling
      final results = await Future.wait(
        affectedQueries.values.map((query) async {
          try {
            final emoji = getAnimalEmoji(query.id);
            developer.log('QueryStreamManager._processBatchedTableChanges: $emoji Refreshing query id="${query.id}" for tables=${uniqueTableNames.join(", ")}', name: 'QueryStreamManager');
            await query.refresh();
            developer.log('QueryStreamManager._processBatchedTableChanges: $emoji Successfully refreshed query id="${query.id}" for tables=${uniqueTableNames.join(", ")}', name: 'QueryStreamManager');
            return null;
          } catch (e) {
            final emoji = getAnimalEmoji(query.id);
            final errorMsg = '$emoji Query ${query.id} refresh failed: $e';
            developer.log('QueryStreamManager._processBatchedTableChanges: $errorMsg', name: 'QueryStreamManager');
            return errorMsg;
          }
        }),
      );

      // Handle any errors that occurred
      final errors = results.where((error) => error != null).toList();
      if (errors.isNotEmpty) {
        developer.log('QueryStreamManager._processBatchedTableChanges: ${errors.length} queries had errors during refresh for tables=${uniqueTableNames.join(", ")}: ${errors.join(", ")}', name: 'QueryStreamManager');
      } else {
        developer.log('QueryStreamManager._processBatchedTableChanges: All queries refreshed successfully for tables=${uniqueTableNames.join(", ")}', name: 'QueryStreamManager');
      }
    } catch (e, stackTrace) {
      developer.log('QueryStreamManager._processBatchedTableChanges: Error during batched table change notification for tables=${uniqueTableNames.join(", ")}', error: e, stackTrace: stackTrace, name: 'QueryStreamManager');
      rethrow;
    }
  }

  /// Process a single table change notification (for backward compatibility and debugging)
  Future<void> _processTableChange(String tableName) async {
    await _processBatchedTableChanges([tableName]);
  }

  /// Notifies all relevant queries that a specific column has been modified
  Future<void> notifyColumnChanged(String tableName, String columnName) async {
    developer.log('QueryStreamManager.notifyColumnChanged: Notifying queries about column="$tableName.$columnName" change, checking ${_queries.length} registered queries', name: 'QueryStreamManager');
    
    try {
      final affectedQueries = _queries.values
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
            final emoji = getAnimalEmoji(query.id);
            developer.log('QueryStreamManager.notifyColumnChanged: $emoji Refreshing query id="${query.id}" for column="$tableName.$columnName"', name: 'QueryStreamManager');
            await query.refresh();
            developer.log('QueryStreamManager.notifyColumnChanged: $emoji Successfully refreshed query id="${query.id}" for column="$tableName.$columnName"', name: 'QueryStreamManager');
            return null;
          } catch (e) {
            final emoji = getAnimalEmoji(query.id);
            final errorMsg = '$emoji Query ${query.id} refresh failed: $e';
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
  int get activeQueryCount => _queries.values.where((q) => q.isActive).length;

  /// Returns the total number of registered queries
  int get totalQueryCount => _queries.length;

  /// Returns the list of currently active streaming queries
  List<StreamingQuery> get activeQueries => 
      _queries.values.where((q) => q.isActive).toList();

  /// Returns all registered streaming queries (active and inactive)
  List<StreamingQuery> get allQueries => _queries.values.toList();

  /// Notifies all relevant queries about multiple table changes at once
  /// This is more efficient than calling notifyTableChanged multiple times
  Future<void> notifyMultipleTablesChanged(List<String> tableNames) async {
    if (tableNames.isEmpty) return;

    try {
      // Collect all affected queries (deduplicated)
      final affectedQueries = <String, StreamingQuery>{};
      
      for (final tableName in tableNames) {
        for (final query in _queries.values) {
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
    developer.log('QueryStreamManager.cleanup: Starting cleanup, checking ${_queries.length} registered queries', name: 'QueryStreamManager');
    
    final inactiveQueries = _queries.entries
        .where((entry) => !entry.value.isActive)
        .map((entry) => entry.key)
        .toList();

    developer.log('QueryStreamManager.cleanup: Found ${inactiveQueries.length} inactive queries to remove: ${inactiveQueries.join(", ")}', name: 'QueryStreamManager');
    
    for (final queryId in inactiveQueries) {
      unregister(queryId);
    }
    
    developer.log('QueryStreamManager.cleanup: Cleanup completed, ${_queries.length} queries remaining', name: 'QueryStreamManager');
  }

  /// Dispose of all queries and clean up
  Future<void> dispose() async {
    developer.log('QueryStreamManager.dispose: Disposing ${_queries.length} registered queries', name: 'QueryStreamManager');
    
    // Clean up debounced table change subscription
    await _tableChangeSubscription.cancel();
    _tableChangeSubject.close();
    
    final disposeFutures = <Future<void>>[];
    
    for (final query in _queries.values) {
      final emoji = getAnimalEmoji(query.id);
      developer.log('QueryStreamManager.dispose: $emoji Disposing query id="${query.id}"', name: 'QueryStreamManager');
      disposeFutures.add(
        query.dispose().catchError((error) {
          developer.log('QueryStreamManager.dispose: $emoji Error disposing query id="${query.id}": $error', name: 'QueryStreamManager');
        })
      );
    }
    
    // Wait for all disposals to complete (with timeout)
    try {
      await Future.wait(disposeFutures).timeout(Duration(seconds: 10));
    } catch (e) {
      developer.log('QueryStreamManager.dispose: Timeout or error during bulk disposal: $e', name: 'QueryStreamManager');
    }
    
    _queries.clear();
    developer.log('QueryStreamManager.dispose: All queries disposed and cleared', name: 'QueryStreamManager');
  }

  /// Debug method to check the current state of the stream manager
  void debugState({String? context}) {
    final contextStr = context != null ? '[$context] ' : '';
    developer.log('${contextStr}QueryStreamManager.debugState: ${_queries.length} total queries, $activeQueryCount active', name: 'QueryStreamManager');
    
    if (_queries.isNotEmpty) {
      for (final query in _queries.values) {
        final emoji = getAnimalEmoji(query.id);
        final tables = query.dependencies.tables.join(', ');
        developer.log('${contextStr}QueryStreamManager.debugState: $emoji Query "${query.id}" - active: ${query.isActive}, tables: {$tables}', name: 'QueryStreamManager');
      }
    } else {
      developer.log('${contextStr}QueryStreamManager.debugState: No queries currently registered', name: 'QueryStreamManager');
    }
  }

  /// Test method to manually trigger table change processing (bypassing debounce)
  Future<void> debugProcessTableChange(String tableName) async {
    developer.log('QueryStreamManager.debugProcessTableChange: Manually processing table change for table="$tableName" (bypassing debounce)', name: 'QueryStreamManager');
    await _processTableChange(tableName);
  }

  /// Test method to check if the debouncing stream is working
  void debugTestDebouncing(String tableName) {
    developer.log('QueryStreamManager.debugTestDebouncing: Testing debouncing stream with table="$tableName"', name: 'QueryStreamManager');
    developer.log('QueryStreamManager.debugTestDebouncing: _tableChangeSubject.isClosed = ${_tableChangeSubject.isClosed}', name: 'QueryStreamManager');
    developer.log('QueryStreamManager.debugTestDebouncing: _tableChangeSubscription.isPaused = ${_tableChangeSubscription.isPaused}', name: 'QueryStreamManager');
    
    // Try adding a test event
    try {
      _tableChangeSubject.add(tableName);
      developer.log('QueryStreamManager.debugTestDebouncing: Successfully added test event to debouncing stream', name: 'QueryStreamManager');
    } catch (e) {
      developer.log('QueryStreamManager.debugTestDebouncing: ERROR adding test event: $e', name: 'QueryStreamManager');
    }
  }

  /// Reset the debouncing stream if it gets into a bad state
  void _resetDebouncingStream() {
    developer.log('QueryStreamManager._resetDebouncingStream: Resetting debouncing stream due to malfunction', name: 'QueryStreamManager');
    
    try {
      // Cancel the old subscription
      _tableChangeSubscription.cancel();
      
      // Close the old subject if it's not already closed
      if (!_tableChangeSubject.isClosed) {
        _tableChangeSubject.close();
      }
    } catch (e) {
      developer.log('QueryStreamManager._resetDebouncingStream: Error cleaning up old stream: $e', name: 'QueryStreamManager');
    }
    
    // Create new subject and subscription with batching
    final newSubject = PublishSubject<String>();
    final newSubscription = newSubject
        .bufferTime(const Duration(milliseconds: 100))
        .where((batch) => batch.isNotEmpty)
        .listen(
          _processBatchedTableChanges,
          onError: (error, stackTrace) {
            developer.log('QueryStreamManager: Error in batched stream processing', error: error, stackTrace: stackTrace, name: 'QueryStreamManager');
          },
        );
    
    // Replace with new instances
    _tableChangeSubject = newSubject;
    _tableChangeSubscription = newSubscription;
    
    developer.log('QueryStreamManager._resetDebouncingStream: Debouncing stream reset complete', name: 'QueryStreamManager');
  }

  @override
  String toString() {
    return 'QueryStreamManager(active: $activeQueryCount, total: $totalQueryCount)';
  }
}