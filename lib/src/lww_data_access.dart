import 'package:sqflite_common/sqflite.dart';
import 'schema_builder.dart';
import 'data_access.dart';
import 'lww_types.dart';

/// Data access layer that provides Last-Writer-Wins conflict resolution.
/// 
/// @deprecated Use DataAccess.createWithLWW() instead for unified functionality
/// This class is maintained for backwards compatibility only.
class LWWDataAccess {
  final DataAccess _dataAccess;

  LWWDataAccess._(this._dataAccess);
  
  /// Factory method to create and initialize LWWDataAccess
  static Future<LWWDataAccess> create({
    required Database database,
    required SchemaBuilder schema,
  }) async {
    final dataAccess = await DataAccess.createWithLWW(database: database, schema: schema);
    return LWWDataAccess._(dataAccess);
  }

  /// Delegate all methods to the underlying DataAccess instance
  Database get database => _dataAccess.database;
  SchemaBuilder get schema => _dataAccess.schema;
  bool get lwwEnabled => _dataAccess.lwwEnabled;

  // Delegate all DataAccess methods
  Future<Map<String, dynamic>?> getByPrimaryKey(String tableName, dynamic primaryKeyValue) =>
      _dataAccess.getByPrimaryKey(tableName, primaryKeyValue);

  Future<int> insert(String tableName, Map<String, dynamic> values) =>
      _dataAccess.insert(tableName, values);

  Future<int> updateByPrimaryKey(String tableName, dynamic primaryKeyValue, Map<String, dynamic> values) =>
      _dataAccess.updateByPrimaryKey(tableName, primaryKeyValue, values);

  Future<int> deleteByPrimaryKey(String tableName, dynamic primaryKeyValue) =>
      _dataAccess.deleteByPrimaryKey(tableName, primaryKeyValue);

  Future<bool> existsByPrimaryKey(String tableName, dynamic primaryKeyValue) =>
      _dataAccess.existsByPrimaryKey(tableName, primaryKeyValue);

  Future<List<Map<String, dynamic>>> getAllWhere(String tableName, {String? where, List<dynamic>? whereArgs, String? orderBy, int? limit, int? offset}) =>
      _dataAccess.getAllWhere(tableName, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit, offset: offset);

  Future<int> count(String tableName, {String? where, List<dynamic>? whereArgs}) =>
      _dataAccess.count(tableName, where: where, whereArgs: whereArgs);

  Future<int> updateWhere(String tableName, Map<String, dynamic> values, {String? where, List<dynamic>? whereArgs}) =>
      _dataAccess.updateWhere(tableName, values, where: where, whereArgs: whereArgs);

  Future<int> deleteWhere(String tableName, {String? where, List<dynamic>? whereArgs}) =>
      _dataAccess.deleteWhere(tableName, where: where, whereArgs: whereArgs);

  Future<BulkLoadResult> bulkLoad(String tableName, List<Map<String, dynamic>> dataset, {BulkLoadOptions options = const BulkLoadOptions()}) =>
      _dataAccess.bulkLoad(tableName, dataset, options: options);

  TableMetadata getTableMetadata(String tableName) =>
      _dataAccess.getTableMetadata(tableName);

  // LWW-specific methods
  Future<void> updateLWWColumn(String tableName, dynamic primaryKeyValue, String columnName, dynamic value, {String? timestamp}) =>
      _dataAccess.updateLWWColumn(tableName, primaryKeyValue, columnName, value, timestamp: timestamp);

  Future<dynamic> getLWWColumnValue(String tableName, dynamic primaryKeyValue, String columnName) =>
      _dataAccess.getLWWColumnValue(tableName, primaryKeyValue, columnName);

  Future<void> applyServerUpdate(String tableName, dynamic primaryKeyValue, Map<String, dynamic> serverData, String serverTimestamp) =>
      _dataAccess.applyServerUpdate(tableName, primaryKeyValue, serverData, serverTimestamp);

  List<PendingOperation> getPendingOperations() =>
      _dataAccess.getPendingOperations();

  void markOperationSynced(String operationId) =>
      _dataAccess.markOperationSynced(operationId);

  void clearSyncedOperations() =>
      _dataAccess.clearSyncedOperations();
}