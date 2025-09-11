import 'package:sqflite_common/sqflite.dart';
import 'schema_builder.dart';
import 'data_access.dart';
import 'data_types.dart';
import 'lww_types.dart';

/// Data access layer that provides Last-Writer-Wins conflict resolution.
/// 
/// Extends the basic DataAccess functionality with support for:
/// - LWW column conflict resolution using HLC timestamps
/// - In-memory cache for immediate UI updates
/// - Pending operations queue for offline sync
/// - Server update conflict resolution
class LWWDataAccess extends DataAccess {
  /// Creates a new LWWDataAccess instance
  LWWDataAccess({
    required super.database,
    required super.schema,
  });

  /// In-memory cache of current LWW column values
  /// Map of tableName -> primaryKey -> columnName -> LWWColumnValue
  final Map<String, Map<dynamic, Map<String, LWWColumnValue>>> _lwwCache = {};
  
  /// Queue of pending operations waiting to be synced to server
  final Map<String, PendingOperation> _pendingOperations = {};

  /// Gets the effective value for a LWW column, considering both DB and cache
  /// Returns the cached value if available, otherwise the DB value
  Future<dynamic> getLWWColumnValue(String tableName, dynamic primaryKeyValue, String columnName) async {
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }

    final column = table.columns.firstWhere(
      (col) => col.name == columnName,
      orElse: () => throw ArgumentError('Column "$columnName" not found in table "$tableName"')
    );

    if (!column.isLWW) {
      // Not a LWW column, use regular data access
      final row = await getByPrimaryKey(tableName, primaryKeyValue);
      return row?[columnName];
    }

    // Check cache first for LWW columns
    final cachedValue = _getCachedLWWValue(tableName, primaryKeyValue, columnName);
    if (cachedValue != null) {
      return cachedValue.value;
    }
    
    // Fall back to DB value if no cached value
    final row = await getByPrimaryKey(tableName, primaryKeyValue);
    return row?[columnName];
  }

  /// Updates a LWW column with conflict resolution
  /// Returns the effective value after conflict resolution
  Future<dynamic> updateLWWColumn(
    String tableName, 
    dynamic primaryKeyValue, 
    String columnName, 
    dynamic newValue, {
    String? explicitTimestamp,
    bool isFromServer = false,
  }) async {
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }

    final column = table.columns.firstWhere(
      (col) => col.name == columnName,
      orElse: () => throw ArgumentError('Column "$columnName" not found in table "$tableName"')
    );

    if (!column.isLWW) {
      throw ArgumentError('Column "$columnName" is not marked for LWW conflict resolution');
    }

    final timestamp = explicitTimestamp ?? SystemColumnUtils.generateHLCTimestamp();
    final newLWWValue = LWWColumnValue(
      value: newValue,
      timestamp: timestamp,
      columnName: columnName,
      isFromServer: isFromServer,
    );

    // Get current cached value if any
    final currentCachedValue = _getCachedLWWValue(tableName, primaryKeyValue, columnName);
    
    // Resolve conflict with cached value
    LWWColumnValue finalValue = newLWWValue;
    if (currentCachedValue != null) {
      finalValue = newLWWValue.resolveConflict(currentCachedValue);
    }

    // Always update cache with the new value (winner of conflict resolution)
    _setCachedLWWValue(tableName, primaryKeyValue, finalValue);

    // If this is not a server update and our value won, add to pending operations
    if (!isFromServer && finalValue == newLWWValue) {
      _addPendingOperation(tableName, primaryKeyValue, columnName, finalValue);
    }

    // Always try to update database (for persistence)
    try {
      await updateByPrimaryKey(tableName, primaryKeyValue, {columnName: finalValue.value});
    } catch (e) {
      // If DB update fails (e.g., offline), keep in cache for later sync
      // The pending operation will handle the eventual sync
    }

    return finalValue.value;
  }

  /// Gets a complete row with all LWW conflicts resolved
  Future<Map<String, dynamic>?> getLWWRow(String tableName, dynamic primaryKeyValue) async {
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }

    // Get base row from database
    final baseRow = await getByPrimaryKey(tableName, primaryKeyValue);
    if (baseRow == null) {
      return null;
    }

    final result = Map<String, dynamic>.from(baseRow);

    // Resolve LWW columns
    for (final column in table.columns) {
      if (column.isLWW) {
        final effectiveValue = await getLWWColumnValue(tableName, primaryKeyValue, column.name);
        if (effectiveValue != null) {
          result[column.name] = effectiveValue;
        }
      }
    }

    return result;
  }

  /// Applies server updates with conflict resolution
  /// Returns a map of columnName -> effectiveValue after conflict resolution
  Future<Map<String, dynamic>> applyServerUpdate(
    String tableName,
    dynamic primaryKeyValue,
    Map<String, dynamic> serverValues,
    String serverTimestamp,
  ) async {
    final result = <String, dynamic>{};
    
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }
    
    for (final entry in serverValues.entries) {
      final columnName = entry.key;
      final serverValue = entry.value;
      
      // Skip system columns
      if (SystemColumns.isSystemColumn(columnName)) {
        continue;
      }

      // Find the column definition
      final column = table.columns.firstWhere(
        (col) => col.name == columnName,
        orElse: () => throw ArgumentError('Column "$columnName" not found in table "$tableName"')
      );

      if (column.isLWW) {
        // Use LWW conflict resolution for LWW columns
        final effectiveValue = await updateLWWColumn(
          tableName,
          primaryKeyValue,
          columnName,
          serverValue,
          explicitTimestamp: serverTimestamp,
          isFromServer: true,
        );
        result[columnName] = effectiveValue;
      } else {
        // For non-LWW columns, just update directly
        await updateByPrimaryKey(tableName, primaryKeyValue, {columnName: serverValue});
        result[columnName] = serverValue;
      }
    }

    return result;
  }

  /// Gets all pending operations that need to be synced to server
  List<PendingOperation> getPendingOperations() {
    return _pendingOperations.values.where((op) => !op.isSynced).toList();
  }

  /// Marks an operation as successfully synced
  void markOperationSynced(String operationId) {
    final operation = _pendingOperations[operationId];
    if (operation != null) {
      _pendingOperations[operationId] = operation.markAsSynced();
    }
  }

  /// Clears all synced operations from the pending queue
  void clearSyncedOperations() {
    _pendingOperations.removeWhere((_, operation) => operation.isSynced);
  }

  /// Clears all pending operations (for testing)
  void clearAllPendingOperations() {
    _pendingOperations.clear();
  }

  /// Helper method to get cached LWW value
  LWWColumnValue? _getCachedLWWValue(String tableName, dynamic primaryKeyValue, String columnName) {
    return _lwwCache[tableName]?[primaryKeyValue]?[columnName];
  }

  /// Helper method to set cached LWW value
  void _setCachedLWWValue(String tableName, dynamic primaryKeyValue, LWWColumnValue value) {
    _lwwCache[tableName] ??= {};
    _lwwCache[tableName]![primaryKeyValue] ??= {};
    _lwwCache[tableName]![primaryKeyValue]![value.columnName] = value;
  }

  /// Helper method to add pending operation for sync
  void _addPendingOperation(String tableName, dynamic primaryKeyValue, String columnName, LWWColumnValue value) {
    final operationId = SystemColumnUtils.generateGuid();
    final operation = PendingOperation(
      id: operationId,
      tableName: tableName,
      operationType: OperationType.update,
      primaryKeyValue: primaryKeyValue,
      columnUpdates: {columnName: value},
      timestamp: value.timestamp,
    );
    
    _pendingOperations[operationId] = operation;
  }
}