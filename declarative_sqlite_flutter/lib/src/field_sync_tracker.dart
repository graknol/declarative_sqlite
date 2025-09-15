import 'dart:async';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'field_sync_status.dart';

/// Manages sync status tracking for form fields, integrating with the 
/// existing ServerSyncManager and DataAccess infrastructure
class FieldSyncTracker {
  FieldSyncTracker({
    required this.dataAccess,
    this.syncManager,
  });
  
  final DataAccess dataAccess;
  final ServerSyncManager? syncManager;
  
  // Track field sync status by table.primaryKey.columnName
  final Map<String, FieldSyncInfo> _fieldStatus = {};
  
  // Controllers for status change streams
  final Map<String, StreamController<FieldSyncInfo>> _statusControllers = {};
  
  /// Gets the current sync status for a field
  FieldSyncInfo getFieldStatus(String tableName, dynamic primaryKey, String columnName) {
    final key = _getFieldKey(tableName, primaryKey, columnName);
    return _fieldStatus[key] ?? const FieldSyncInfo(status: FieldSyncStatus.local);
  }
  
  /// Updates the sync status for a field
  void updateFieldStatus(String tableName, dynamic primaryKey, String columnName, FieldSyncInfo status) {
    final key = _getFieldKey(tableName, primaryKey, columnName);
    _fieldStatus[key] = status;
    
    // Notify listeners
    final controller = _statusControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(status);
    }
  }
  
  /// Gets a stream of status changes for a field
  Stream<FieldSyncInfo> getFieldStatusStream(String tableName, dynamic primaryKey, String columnName) {
    final key = _getFieldKey(tableName, primaryKey, columnName);
    
    if (!_statusControllers.containsKey(key)) {
      _statusControllers[key] = StreamController<FieldSyncInfo>.broadcast();
    }
    
    return _statusControllers[key]!.stream;
  }
  
  /// Marks a field as having local changes (unsaved)
  void markFieldAsLocal(String tableName, dynamic primaryKey, String columnName) {
    updateFieldStatus(
      tableName,
      primaryKey,
      columnName,
      const FieldSyncInfo(status: FieldSyncStatus.local),
    );
  }
  
  /// Marks a field as saved to database
  void markFieldAsSaved(String tableName, dynamic primaryKey, String columnName, {ChangeAttribution? attribution}) {
    updateFieldStatus(
      tableName,
      primaryKey,
      columnName,
      FieldSyncInfo(
        status: FieldSyncStatus.saved,
        attribution: attribution,
        lastSyncTime: DateTime.now(),
      ),
    );
  }
  
  /// Marks a field as synced to server
  void markFieldAsSynced(String tableName, dynamic primaryKey, String columnName, {ChangeAttribution? attribution}) {
    updateFieldStatus(
      tableName,
      primaryKey,
      columnName,
      FieldSyncInfo(
        status: FieldSyncStatus.synced,
        attribution: attribution,
        lastSyncTime: DateTime.now(),
      ),
    );
  }
  
  /// Checks if a field has pending changes based on LWW timestamps
  Future<bool> hasFieldPendingSync(String tableName, dynamic primaryKey, String columnName) async {
    if (syncManager == null) return false;
    
    try {
      // Check if there are pending operations for this field
      final operations = await syncManager!.getPendingOperations();
      return operations.any((op) =>
          op.tableName == tableName &&
          op.primaryKeyValue == primaryKey &&
          op.columnUpdates.containsKey(columnName));
    } catch (e) {
      return false;
    }
  }
  
  /// Syncs field status with the current state of the database and sync manager
  Future<void> syncFieldStatus(String tableName, dynamic primaryKey, String columnName) async {
    try {
      // Check if there are pending sync operations
      final hasPending = await hasFieldPendingSync(tableName, primaryKey, columnName);
      
      if (hasPending) {
        // Has pending sync - mark as saved but not synced
        markFieldAsSaved(tableName, primaryKey, columnName);
      } else {
        // Check if the field exists in database and is synced
        final record = await dataAccess.getByPrimaryKey(tableName, primaryKey);
        if (record != null && record.containsKey(columnName)) {
          // Try to determine if this came from server by checking LWW metadata
          final lwwTimestamp = record['${columnName}_timestamp'];
          final isFromServer = record['${columnName}_is_from_server'] == 1;
          
          if (isFromServer) {
            // Try to extract user attribution from LWW metadata
            ChangeAttribution? attribution;
            final userId = record['${columnName}_user_id']?.toString();
            final userName = record['${columnName}_user_name']?.toString();
            if (userId != null && userName != null) {
              attribution = ChangeAttribution(
                userId: userId,
                userName: userName,
                timestamp: DateTime.now(), // Could parse from LWW timestamp if available
              );
            }
            
            markFieldAsSynced(tableName, primaryKey, columnName, attribution: attribution);
          } else {
            markFieldAsSaved(tableName, primaryKey, columnName);
          }
        } else {
          markFieldAsLocal(tableName, primaryKey, columnName);
        }
      }
    } catch (e) {
      // On error, assume local status
      markFieldAsLocal(tableName, primaryKey, columnName);
    }
  }
  
  /// Cleanup method to close all streams
  void dispose() {
    for (final controller in _statusControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _statusControllers.clear();
    _fieldStatus.clear();
  }
  
  String _getFieldKey(String tableName, dynamic primaryKey, String columnName) {
    return '$tableName.$primaryKey.$columnName';
  }
}

/// Extension to provide easy access to sync tracking from AutoForm contexts
extension DataAccessSyncTracking on DataAccess {
  /// Creates a field sync tracker for this DataAccess instance
  FieldSyncTracker createSyncTracker({ServerSyncManager? syncManager}) {
    return FieldSyncTracker(
      dataAccess: this,
      syncManager: syncManager,
    );
  }
}