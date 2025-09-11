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
/// - Per-column timestamp tracking in database
class LWWDataAccess extends DataAccess {
  /// Creates a new LWWDataAccess instance
  LWWDataAccess._({
    required super.database,
    required super.schema,
  });
  
  /// Factory method to create and initialize LWWDataAccess
  static Future<LWWDataAccess> create({
    required Database database,
    required SchemaBuilder schema,
  }) async {
    final instance = LWWDataAccess._(database: database, schema: schema);
    await instance._initializeLWWTables();
    return instance;
  }

  /// Name of the internal table that stores LWW column timestamps
  static const String _lwwTimestampsTable = '_lww_column_timestamps';

  /// In-memory cache of current LWW column values
  /// Map of tableName -> primaryKey -> columnName -> LWWColumnValue
  final Map<String, Map<dynamic, Map<String, LWWColumnValue>>> _lwwCache = {};
  
  /// Queue of pending operations waiting to be synced to server
  final Map<String, PendingOperation> _pendingOperations = {};

  /// Initializes the LWW metadata table for storing per-column timestamps
  Future<void> _initializeLWWTables() async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $_lwwTimestampsTable (
        table_name TEXT NOT NULL,
        primary_key_value TEXT NOT NULL,
        column_name TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_from_server INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (table_name, primary_key_value, column_name)
      )
    ''');
  }

  /// Stores a timestamp for a specific LWW column
  Future<void> _storeLWWTimestamp(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
    String timestamp, {
    bool isFromServer = false,
  }) async {
    await database.execute(
      '''INSERT OR REPLACE INTO $_lwwTimestampsTable 
         (table_name, primary_key_value, column_name, timestamp, is_from_server)
         VALUES (?, ?, ?, ?, ?)''',
      [tableName, primaryKeyValue.toString(), columnName, timestamp, isFromServer ? 1 : 0],
    );
  }

  /// Gets the stored timestamp and source info for a specific LWW column
  Future<(String, bool)?> _getLWWTimestampInfo(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
  ) async {
    final result = await database.query(
      _lwwTimestampsTable,
      columns: ['timestamp', 'is_from_server'],
      where: 'table_name = ? AND primary_key_value = ? AND column_name = ?',
      whereArgs: [tableName, primaryKeyValue.toString(), columnName],
    );
    
    if (result.isNotEmpty) {
      final row = result.first;
      final timestamp = row['timestamp'] as String;
      final isFromServer = (row['is_from_server'] as int) == 1;
      return (timestamp, isFromServer);
    }
    
    return null;
  }

  /// Gets the effective value for a LWW column, considering cache, DB, and stored timestamps
  /// Returns the cached value if available, otherwise determines from DB + timestamp
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

    // For LWW columns, check cache first
    final cachedValue = _getCachedLWWValue(tableName, primaryKeyValue, columnName);
    if (cachedValue != null) {
      return cachedValue.value;
    }
    
    // No cached value, get from DB
    final row = await getByPrimaryKey(tableName, primaryKeyValue);
    if (row == null) {
      return null;
    }
    
    return row[columnName];
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

    // Check cache first
    final cachedValue = _getCachedLWWValue(tableName, primaryKeyValue, columnName);
    LWWColumnValue? currentValue = cachedValue;

    // If no cached value, try to reconstruct from DB + stored timestamp
    if (currentValue == null) {
      final row = await getByPrimaryKey(tableName, primaryKeyValue);
      if (row != null) {
        final timestampInfo = await _getLWWTimestampInfo(tableName, primaryKeyValue, columnName);
        if (timestampInfo != null) {
          final (storedTimestamp, isFromServer) = timestampInfo;
          currentValue = LWWColumnValue(
            value: row[columnName],
            timestamp: storedTimestamp,
            columnName: columnName,
            isFromServer: isFromServer,
          );
        }
      }
    }

    // Resolve conflict
    LWWColumnValue finalValue = newLWWValue;
    if (currentValue != null) {
      finalValue = newLWWValue.resolveConflict(currentValue);
    }

    // Update cache and DB if our value won
    if (finalValue == newLWWValue) {
      _setCachedLWWValue(tableName, primaryKeyValue, finalValue);
      await _storeLWWTimestamp(tableName, primaryKeyValue, columnName, finalValue.timestamp, 
                              isFromServer: finalValue.isFromServer);
      
      try {
        await updateByPrimaryKey(tableName, primaryKeyValue, {columnName: finalValue.value});
      } catch (e) {
        // If DB update fails, keep in cache and timestamp store
      }

      // Add to pending operations if it's a user update
      if (!isFromServer) {
        _addPendingOperation(tableName, primaryKeyValue, columnName, finalValue);
      }
    } else {
      // Our value lost, but update cache with winner
      _setCachedLWWValue(tableName, primaryKeyValue, finalValue);
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

  /// Override insert to store initial LWW timestamps
  @override
  Future<int> insert(String tableName, Map<String, dynamic> values) async {
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }

    // Do the regular insert
    final rowId = await super.insert(tableName, values);

    // Get the primary key value for the inserted row
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    dynamic primaryKeyValue = rowId;
    
    // For composite primary keys, we need to extract the key from values
    if (primaryKeyColumns.length > 1) {
      primaryKeyValue = primaryKeyColumns.map((col) => values[col]).join('|');
    } else if (primaryKeyColumns.length == 1 && primaryKeyColumns.first != 'id') {
      primaryKeyValue = values[primaryKeyColumns.first];
    }

    // Store initial timestamps for LWW columns
    final currentTimestamp = SystemColumnUtils.generateHLCTimestamp();
    for (final column in table.columns) {
      if (column.isLWW && values.containsKey(column.name)) {
        await _storeLWWTimestamp(tableName, primaryKeyValue, column.name, currentTimestamp,
                                isFromServer: false); // Initial inserts are considered user operations
      }
    }

    return rowId;
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