import 'package:meta/meta.dart';
import 'data_access.dart';

/// Represents a value with its Last-Writer-Wins timestamp for conflict resolution
@immutable
class LWWColumnValue {
  const LWWColumnValue({
    required this.value,
    required this.timestamp,
    required this.columnName,
    this.isFromServer = false,
  });

  /// The actual column value
  final dynamic value;
  
  /// HLC timestamp when this value was last updated
  final String timestamp;
  
  /// Name of the column this value belongs to
  final String columnName;
  
  /// Whether this value came from a server update (vs local user edit)
  final bool isFromServer;

  /// Creates a new LWWColumnValue with updated value and current timestamp
  LWWColumnValue withNewValue(dynamic newValue, {bool fromServer = false}) {
    return LWWColumnValue(
      value: newValue,
      timestamp: SystemColumnUtils.generateHLCTimestamp(),
      columnName: columnName,
      isFromServer: fromServer,
    );
  }

  /// Creates a new LWWColumnValue with specific timestamp (for server updates)
  LWWColumnValue withTimestamp(dynamic newValue, String newTimestamp, {bool fromServer = false}) {
    return LWWColumnValue(
      value: newValue,
      timestamp: newTimestamp,
      columnName: columnName,
      isFromServer: fromServer,
    );
  }

  /// Compares two LWW values and returns the one with the newer timestamp
  /// Returns this value if timestamps are equal (LWW default behavior)
  LWWColumnValue resolveConflict(LWWColumnValue other) {
    if (other.columnName != columnName) {
      throw ArgumentError('Cannot resolve conflict between different columns: $columnName vs ${other.columnName}');
    }
    
    // Compare HLC timestamps as integers
    final thisTimestamp = int.tryParse(timestamp) ?? 0;
    final otherTimestamp = int.tryParse(other.timestamp) ?? 0;
    
    return otherTimestamp > thisTimestamp ? other : this;
  }

  /// Checks if this value is newer than the other
  bool isNewerThan(LWWColumnValue other) {
    final thisTimestamp = int.tryParse(timestamp) ?? 0;
    final otherTimestamp = int.tryParse(other.timestamp) ?? 0;
    return thisTimestamp > otherTimestamp;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LWWColumnValue &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          timestamp == other.timestamp &&
          columnName == other.columnName &&
          isFromServer == other.isFromServer;

  @override
  int get hashCode =>
      value.hashCode ^
      timestamp.hashCode ^
      columnName.hashCode ^
      isFromServer.hashCode;

  @override
  String toString() => 'LWWColumnValue($columnName: $value @ $timestamp${isFromServer ? ' [server]' : ''})';
}

/// Represents a pending operation that needs to be synced to the server
@immutable
class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.tableName,
    required this.operationType,
    required this.primaryKeyValue,
    required this.columnUpdates,
    required this.timestamp,
    this.isSynced = false,
  });

  /// Unique identifier for this operation
  final String id;
  
  /// Name of the table being modified
  final String tableName;
  
  /// Type of operation (insert, update, delete)
  final OperationType operationType;
  
  /// Primary key value of the row being modified
  final dynamic primaryKeyValue;
  
  /// Map of column name to LWWColumnValue for updates
  final Map<String, LWWColumnValue> columnUpdates;
  
  /// Timestamp when this operation was created
  final String timestamp;
  
  /// Whether this operation has been successfully synced to server
  final bool isSynced;

  /// Creates a copy of this operation marked as synced
  PendingOperation markAsSynced() {
    return PendingOperation(
      id: id,
      tableName: tableName,
      operationType: operationType,
      primaryKeyValue: primaryKeyValue,
      columnUpdates: columnUpdates,
      timestamp: timestamp,
      isSynced: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingOperation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PendingOperation($id: $operationType on $tableName${isSynced ? ' [synced]' : ''})';
}

/// Types of database operations that can be pending sync
enum OperationType {
  insert,
  update, 
  delete,
}