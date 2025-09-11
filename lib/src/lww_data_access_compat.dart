import 'package:sqflite_common/sqflite.dart';
import 'schema_builder.dart';
import 'data_access.dart';
import 'lww_types.dart';

/// Data access layer that provides Last-Writer-Wins conflict resolution.
/// 
/// @deprecated Use DataAccess.createWithLWW() instead for unified functionality
/// This class is maintained for backwards compatibility only.
class LWWDataAccess extends DataAccess {
  /// Creates a new LWWDataAccess instance
  LWWDataAccess._({
    required super.database,
    required super.schema,
  }) : super._(lwwEnabled: true);
  
  /// Factory method to create and initialize LWWDataAccess
  static Future<LWWDataAccess> create({
    required Database database,
    required SchemaBuilder schema,
  }) async {
    final instance = LWWDataAccess._(database: database, schema: schema);
    await instance._initializeLWWTables();
    return instance;
  }

  /// Updates a LWW column with conflict resolution
  /// Returns the effective value after conflict resolution
  /// @deprecated Use the inherited updateLWWColumn method instead
  Future<dynamic> updateLWWColumnLegacy(
    String tableName, 
    dynamic primaryKeyValue, 
    String columnName, 
    dynamic newValue, {
    String? explicitTimestamp,
    bool isFromServer = false,
  }) async {
    // Call the parent method with the same signature
    await super.updateLWWColumn(
      tableName, 
      primaryKeyValue, 
      columnName, 
      newValue, 
      timestamp: explicitTimestamp,
    );
    
    // Return the new value for backwards compatibility
    return newValue;
  }

  /// Gets current LWW column value from cache or database
  /// @deprecated Use the inherited getLWWColumnValue method instead
  Future<dynamic> getLWWColumnValueLegacy(
    String tableName, 
    dynamic primaryKeyValue, 
    String columnName,
  ) async {
    return await super.getLWWColumnValue(tableName, primaryKeyValue, columnName);
  }

  /// Applies server update with conflict resolution
  /// @deprecated Use the inherited applyServerUpdate method instead
  Future<void> applyServerUpdateLegacy(
    String tableName,
    dynamic primaryKeyValue,
    Map<String, dynamic> serverData,
    String serverTimestamp,
  ) async {
    return await super.applyServerUpdate(tableName, primaryKeyValue, serverData, serverTimestamp);
  }

  /// Gets all pending operations waiting for server sync
  /// @deprecated Use the inherited getPendingOperations method instead
  List<PendingOperation> getPendingOperationsLegacy() {
    return super.getPendingOperations();
  }

  /// Marks an operation as synced and removes it from the pending queue
  /// @deprecated Use the inherited markOperationSynced method instead
  void markOperationSyncedLegacy(String operationId) {
    super.markOperationSynced(operationId);
  }

  /// Clears all synced operations from the pending queue
  /// @deprecated Use the inherited clearSyncedOperations method instead
  void clearSyncedOperationsLegacy() {
    super.clearSyncedOperations();
  }
}