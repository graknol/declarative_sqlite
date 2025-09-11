import 'package:sqflite_common/sqflite.dart';
import 'schema_builder.dart';
import 'table_builder.dart';
import 'column_builder.dart';
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
    final serializedPrimaryKey = _serializePrimaryKey(tableName, primaryKeyValue);
    await database.execute(
      '''INSERT OR REPLACE INTO $_lwwTimestampsTable 
         (table_name, primary_key_value, column_name, timestamp, is_from_server)
         VALUES (?, ?, ?, ?, ?)''',
      [tableName, serializedPrimaryKey, columnName, timestamp, isFromServer ? 1 : 0],
    );
  }

  /// Stores a timestamp for a specific LWW column using transaction
  Future<void> _storeLWWTimestampTxn(
    DatabaseExecutor txn,
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
    String timestamp, {
    bool isFromServer = false,
  }) async {
    final serializedPrimaryKey = _serializePrimaryKey(tableName, primaryKeyValue);
    await txn.execute(
      '''INSERT OR REPLACE INTO $_lwwTimestampsTable 
         (table_name, primary_key_value, column_name, timestamp, is_from_server)
         VALUES (?, ?, ?, ?, ?)''',
      [tableName, serializedPrimaryKey, columnName, timestamp, isFromServer ? 1 : 0],
    );
  }
  Future<(String, bool)?> _getLWWTimestampInfo(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
  ) async {
    final serializedPrimaryKey = _serializePrimaryKey(tableName, primaryKeyValue);
    final result = await database.query(
      _lwwTimestampsTable,
      columns: ['timestamp', 'is_from_server'],
      where: 'table_name = ? AND primary_key_value = ? AND column_name = ?',
      whereArgs: [tableName, serializedPrimaryKey, columnName],
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
    dynamic primaryKeyValue;
    
    // For composite primary keys, we need to extract the key from values  
    if (primaryKeyColumns.length > 1) {
      // Build a map of primary key values for composite keys
      primaryKeyValue = <String, dynamic>{};
      for (final col in primaryKeyColumns) {
        primaryKeyValue[col] = values[col];
      }
    } else if (primaryKeyColumns.length == 1 && primaryKeyColumns.first != 'id') {
      primaryKeyValue = values[primaryKeyColumns.first];
    } else {
      // Default to rowId for auto-increment primary key
      primaryKeyValue = rowId;
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

  /// Serializes a primary key value for storage in the LWW timestamp table
  /// Handles single primary keys, composite primary keys, and different data types
  String _serializePrimaryKey(String tableName, dynamic primaryKeyValue) {
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }

    final primaryKeyColumns = table.getPrimaryKeyColumns();
    if (primaryKeyColumns.isEmpty) {
      throw ArgumentError('Table "$tableName" has no primary key');
    }

    if (primaryKeyColumns.length == 1) {
      // Single primary key - encode the value directly
      final columnName = primaryKeyColumns.first;
      final column = table.columns.firstWhere((col) => col.name == columnName);
      final encodedValue = DataTypeUtils.encodeValue(primaryKeyValue, column.dataType);
      return encodedValue?.toString() ?? 'NULL';
    } else {
      // Composite primary key - serialize as JSON-like structure
      final keyParts = <String>[];
      
      if (primaryKeyValue is Map<String, dynamic>) {
        // Map format: encode each column value
        for (final columnName in primaryKeyColumns) {
          if (!primaryKeyValue.containsKey(columnName)) {
            throw ArgumentError('Primary key value map is missing column: $columnName');
          }
          final column = table.columns.firstWhere((col) => col.name == columnName);
          final rawValue = primaryKeyValue[columnName];
          final encodedValue = DataTypeUtils.encodeValue(rawValue, column.dataType);
          keyParts.add('$columnName:${encodedValue ?? 'NULL'}');
        }
      } else if (primaryKeyValue is List) {
        // List format: encode values in order
        if (primaryKeyValue.length != primaryKeyColumns.length) {
          throw ArgumentError('Primary key value list length (${primaryKeyValue.length}) does not match number of primary key columns (${primaryKeyColumns.length})');
        }
        for (int i = 0; i < primaryKeyColumns.length; i++) {
          final columnName = primaryKeyColumns[i];
          final column = table.columns.firstWhere((col) => col.name == columnName);
          final rawValue = primaryKeyValue[i];
          final encodedValue = DataTypeUtils.encodeValue(rawValue, column.dataType);
          keyParts.add('$columnName:${encodedValue ?? 'NULL'}');
        }
      } else {
        throw ArgumentError('Composite primary key requires Map<String, dynamic> or List for primaryKeyValue, got ${primaryKeyValue.runtimeType}');
      }
      
      return keyParts.join('|');
    }
  }

  /// Override bulkLoad to add LWW conflict resolution support
  @override
  Future<BulkLoadResult> bulkLoad(
    String tableName,
    List<Map<String, dynamic>> dataset, {
    BulkLoadOptions options = const BulkLoadOptions(),
  }) async {
    if (dataset.isEmpty) {
      return BulkLoadResult(
        rowsProcessed: 0,
        rowsInserted: 0,
        rowsUpdated: 0,
        rowsSkipped: 0,
        errors: const [],
      );
    }

    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }

    // Check for LWW columns and validate timestamps
    final lwwColumns = table.columns.where((col) => col.isLWW).toList();
    if (lwwColumns.isNotEmpty) {
      _validateLWWTimestamps(tableName, dataset, lwwColumns, options);
    }

    // If there are no LWW columns, use the regular bulkLoad
    if (lwwColumns.isEmpty) {
      return super.bulkLoad(tableName, dataset, options: options);
    }

    // Process LWW-enabled bulk load
    return _bulkLoadWithLWW(tableName, dataset, options, lwwColumns);
  }

  /// Validates that LWW timestamps are provided for all LWW columns
  void _validateLWWTimestamps(
    String tableName,
    List<Map<String, dynamic>> dataset,
    List<ColumnBuilder> lwwColumns,
    BulkLoadOptions options,
  ) {
    // If no LWW timestamps provided, reject LWW column updates
    if (options.lwwTimestamps == null || options.lwwTimestamps!.isEmpty) {
      final lwwColumnNames = lwwColumns.map((col) => col.name).toSet();
      final datasetColumns = dataset.first.keys.toSet();
      final lwwColumnsInDataset = lwwColumnNames.intersection(datasetColumns);
      
      if (lwwColumnsInDataset.isNotEmpty) {
        throw ArgumentError(
          'Table "$tableName" has LWW columns ${lwwColumnsInDataset.join(', ')} '
          'but no HLC timestamps were provided. Use options.lwwTimestamps to specify timestamps for LWW columns.'
        );
      }
    } else {
      // Validate that timestamps are provided for all LWW columns in the dataset
      final providedTimestamps = options.lwwTimestamps!.keys.toSet();
      
      for (final row in dataset) {
        for (final lwwColumn in lwwColumns) {
          if (row.containsKey(lwwColumn.name) && !providedTimestamps.contains(lwwColumn.name)) {
            throw ArgumentError(
              'Row contains LWW column "${lwwColumn.name}" but no HLC timestamp provided for it. '
              'All LWW columns must have timestamps in options.lwwTimestamps.'
            );
          }
        }
      }
    }
  }

  /// Performs bulk load with LWW conflict resolution
  Future<BulkLoadResult> _bulkLoadWithLWW(
    String tableName,
    List<Map<String, dynamic>> dataset,
    BulkLoadOptions options,
    List<ColumnBuilder> lwwColumns,
  ) async {
    final table = schema.getTable(tableName)!;
    final metadata = getTableMetadata(tableName);
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    
    // Analyze dataset columns vs table columns
    final datasetColumns = dataset.first.keys.toSet();
    final tableColumns = metadata.columns.keys.toSet();
    final validColumns = datasetColumns.intersection(tableColumns);
    
    final errors = <String>[];
    var rowsProcessed = 0;
    var rowsInserted = 0;
    var rowsUpdated = 0;
    var rowsSkipped = 0;
    
    // Check if upsert mode is possible (requires primary key)
    if (options.upsertMode && primaryKeyColumns.isEmpty) {
      throw ArgumentError('Upsert mode requires a primary key, but table "$tableName" has no primary key');
    }
    
    // Pre-validate that required columns can be satisfied
    final missingRequiredColumns = metadata.requiredColumns.toSet()
        .difference(validColumns);
    
    if (missingRequiredColumns.isNotEmpty && !options.allowPartialData) {
      throw ArgumentError(
        'Required columns are missing from dataset: ${missingRequiredColumns.join(', ')}. '
        'Set allowPartialData to true to skip rows missing required columns.'
      );
    }
    
    await database.transaction((txn) async {
      // Clear table if requested
      if (options.clearTableFirst) {
        await txn.delete(tableName);
      }
      
      final batchSize = options.batchSize;
      
      for (var i = 0; i < dataset.length; i += batchSize) {
        final endIndex = (i + batchSize < dataset.length) ? i + batchSize : dataset.length;
        
        for (var j = i; j < endIndex; j++) {
          final row = dataset[j];
          rowsProcessed++;
          
          try {
            // Filter row to only include valid table columns
            final filteredRow = <String, dynamic>{};
            for (final column in validColumns) {
              if (row.containsKey(column)) {
                filteredRow[column] = row[column];
              }
            }
            
            // Check if required columns are satisfied for this specific row
            final rowMissingRequired = metadata.requiredColumns.toSet()
                .difference(filteredRow.keys.toSet());
            
            if (rowMissingRequired.isNotEmpty) {
              if (options.allowPartialData) {
                rowsSkipped++;
                if (options.collectErrors) {
                  errors.add('Row $j: Missing required columns: ${rowMissingRequired.join(', ')}');
                }
                continue;
              } else {
                throw ArgumentError('Row $j: Missing required columns: ${rowMissingRequired.join(', ')}');
              }
            }
            
            // Encode date columns (but not LWW columns yet)
            final nonLWWColumns = <String, ColumnBuilder>{};
            for (final entry in metadata.columns.entries) {
              if (!entry.value.isLWW) {
                nonLWWColumns[entry.key] = entry.value;
              }
            }
            final encodedRow = DataTypeUtils.encodeRow(filteredRow, nonLWWColumns);
            
            // Validate the encoded row data if validation is enabled
            if (options.validateData) {
              _validateInsertValues(table, encodedRow);
            }
            
            if (options.upsertMode && primaryKeyColumns.isNotEmpty) {
              // Upsert mode with LWW conflict resolution
              final result = await _upsertRowWithLWW(
                txn, tableName, table, encodedRow, options, lwwColumns, j
              );
              
              if (result == 'inserted') {
                rowsInserted++;
              } else if (result == 'updated') {
                rowsUpdated++;
              } else if (result == 'skipped') {
                rowsSkipped++;
                if (options.collectErrors) {
                  errors.add('Row $j: Missing primary key values for upsert mode');
                }
              }
            } else {
              // Insert-only mode with LWW timestamps
              await _insertRowWithLWW(txn, tableName, encodedRow, options, lwwColumns);
              rowsInserted++;
            }
          } catch (e) {
            if (options.allowPartialData) {
              rowsSkipped++;
              if (options.collectErrors) {
                errors.add('Row $j: ${e.toString()}');
              }
            } else {
              rethrow;
            }
          }
        }
      }
    });
    
    return BulkLoadResult(
      rowsProcessed: rowsProcessed,
      rowsInserted: rowsInserted,
      rowsUpdated: rowsUpdated,
      rowsSkipped: rowsSkipped,
      errors: errors,
    );
  }

  /// Inserts a row with LWW timestamp tracking
  Future<void> _insertRowWithLWW(
    DatabaseExecutor txn,
    String tableName,
    Map<String, dynamic> encodedRow,
    BulkLoadOptions options,
    List<ColumnBuilder> lwwColumns,
  ) async {
    // Add system columns
    final insertValues = SystemColumnUtils.ensureSystemColumns(encodedRow);
    await txn.insert(tableName, insertValues);
    
    // Store LWW timestamps for any LWW columns present
    if (options.lwwTimestamps != null) {
      final table = schema.getTable(tableName)!;
      final primaryKeyColumns = table.getPrimaryKeyColumns();
      
      // Determine primary key value from inserted row
      dynamic primaryKeyValue;
      if (primaryKeyColumns.length == 1) {
        primaryKeyValue = insertValues[primaryKeyColumns.first];
      } else {
        primaryKeyValue = <String, dynamic>{};
        for (final col in primaryKeyColumns) {
          primaryKeyValue[col] = insertValues[col];
        }
      }
      
      // Store timestamps for LWW columns
      for (final lwwColumn in lwwColumns) {
        if (encodedRow.containsKey(lwwColumn.name) && 
            options.lwwTimestamps!.containsKey(lwwColumn.name)) {
          await _storeLWWTimestampTxn(
            txn,
            tableName,
            primaryKeyValue,
            lwwColumn.name,
            options.lwwTimestamps![lwwColumn.name]!,
            isFromServer: options.isFromServer,
          );
        }
      }
    }
  }

  /// Upserts a row with LWW conflict resolution
  Future<String> _upsertRowWithLWW(
    DatabaseExecutor txn,
    String tableName,
    TableBuilder table,
    Map<String, dynamic> encodedRow,
    BulkLoadOptions options,
    List<ColumnBuilder> lwwColumns,
    int rowIndex,
  ) async {
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    final primaryKeyValues = <String, dynamic>{};
    var hasPrimaryKeyValues = true;
    
    for (final pkColumn in primaryKeyColumns) {
      if (encodedRow.containsKey(pkColumn)) {
        primaryKeyValues[pkColumn] = encodedRow[pkColumn];
      } else {
        hasPrimaryKeyValues = false;
        break;
      }
    }
    
    if (!hasPrimaryKeyValues) {
      return 'skipped';
    }
    
    // Check if row exists
    dynamic pkValue = primaryKeyColumns.length == 1 
        ? primaryKeyValues[primaryKeyColumns.first]
        : primaryKeyValues;
    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, pkValue, table);
    final existingRows = await txn.query(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );
    
    if (existingRows.isNotEmpty) {
      // Row exists, update with LWW conflict resolution
      await _updateRowWithLWW(txn, tableName, pkValue, encodedRow, options, lwwColumns);
      return 'updated';
    } else {
      // Row doesn't exist, insert it
      await _insertRowWithLWW(txn, tableName, encodedRow, options, lwwColumns);
      return 'inserted';
    }
  }

  /// Validates that insert values meet table constraints.
  void _validateInsertValues(TableBuilder table, Map<String, dynamic> values) {
    // Check that all NOT NULL columns without defaults are provided
    // Skip system columns as they are automatically populated
    for (final column in table.columns) {
      if (column.constraints.contains(ConstraintType.notNull) && 
          column.defaultValue == null &&
          !SystemColumns.isSystemColumn(column.name) &&
          !values.containsKey(column.name)) {
        throw ArgumentError('Required column "${column.name}" is missing from insert values');
      }
    }
    
    // Validate that provided columns exist in the table
    for (final columnName in values.keys) {
      if (!table.columns.any((col) => col.name == columnName)) {
        throw ArgumentError('Column "$columnName" does not exist in table "${table.name}"');
      }
    }
  }

  /// Builds a WHERE clause and arguments for primary key matching
  (String, List<dynamic>) _buildPrimaryKeyWhereClause(List<String> primaryKeyColumns, dynamic primaryKeyValue, TableBuilder table) {
    if (primaryKeyColumns.length == 1) {
      // Single primary key
      final column = table.columns.firstWhere((col) => col.name == primaryKeyColumns.first);
      final encodedValue = DataTypeUtils.encodeValue(primaryKeyValue, column.dataType);
      return ('${primaryKeyColumns.first} = ?', [encodedValue]);
    } else {
      // Composite primary key
      if (primaryKeyValue is Map<String, dynamic>) {
        final whereConditions = <String>[];
        final whereArgs = <dynamic>[];
        
        for (final columnName in primaryKeyColumns) {
          if (!primaryKeyValue.containsKey(columnName)) {
            throw ArgumentError('Primary key value map is missing column: $columnName');
          }
          whereConditions.add('$columnName = ?');
          
          final column = table.columns.firstWhere((col) => col.name == columnName);
          final encodedValue = DataTypeUtils.encodeValue(primaryKeyValue[columnName], column.dataType);
          whereArgs.add(encodedValue);
        }
        
        return (whereConditions.join(' AND '), whereArgs);
      } else if (primaryKeyValue is List) {
        if (primaryKeyValue.length != primaryKeyColumns.length) {
          throw ArgumentError('Primary key value list length (${primaryKeyValue.length}) does not match number of primary key columns (${primaryKeyColumns.length})');
        }
        
        final whereConditions = <String>[];
        final encodedArgs = <dynamic>[];
        for (int i = 0; i < primaryKeyColumns.length; i++) {
          whereConditions.add('${primaryKeyColumns[i]} = ?');
          
          final columnName = primaryKeyColumns[i];
          final column = table.columns.firstWhere((col) => col.name == columnName);
          final encodedValue = DataTypeUtils.encodeValue(primaryKeyValue[i], column.dataType);
          encodedArgs.add(encodedValue);
        }
        
        return (whereConditions.join(' AND '), encodedArgs);
      } else {
        throw ArgumentError('Composite primary key requires Map<String, dynamic> or List for primaryKeyValue, got ${primaryKeyValue.runtimeType}');
      }
    }
  }

  /// Update a row with LWW conflict resolution
  Future<void> _updateRowWithLWW(
    DatabaseExecutor txn,
    String tableName,
    dynamic primaryKeyValue,
    Map<String, dynamic> encodedRow,
    BulkLoadOptions options,
    List<ColumnBuilder> lwwColumns,
  ) async {
    final updateValues = <String, dynamic>{};
    
    // Process non-LWW columns normally
    for (final entry in encodedRow.entries) {
      final columnName = entry.key;
      final isLWWColumn = lwwColumns.any((col) => col.name == columnName);
      
      if (!isLWWColumn) {
        updateValues[columnName] = entry.value;
      }
    }
    
    // Process LWW columns with conflict resolution
    if (options.lwwTimestamps != null) {
      for (final lwwColumn in lwwColumns) {
        if (encodedRow.containsKey(lwwColumn.name) && 
            options.lwwTimestamps!.containsKey(lwwColumn.name)) {
          
          final newValue = encodedRow[lwwColumn.name];
          final newTimestamp = options.lwwTimestamps![lwwColumn.name]!;
          
          // Get current timestamp for this LWW column
          final currentTimestampInfo = await _getLWWTimestampInfo(
            tableName,
            primaryKeyValue,
            lwwColumn.name,
          );
          
          bool shouldUpdate = true;
          if (currentTimestampInfo != null) {
            final (currentTimestamp, _) = currentTimestampInfo;
            final currentTimestampInt = int.tryParse(currentTimestamp) ?? 0;
            final newTimestampInt = int.tryParse(newTimestamp) ?? 0;
            
            // Only update if new timestamp is newer or equal (Last-Writer-Wins)
            shouldUpdate = newTimestampInt >= currentTimestampInt;
          }
          
          if (shouldUpdate) {
            updateValues[lwwColumn.name] = newValue;
            
            // Store the new timestamp
            await _storeLWWTimestampTxn(
              txn,
              tableName,
              primaryKeyValue,
              lwwColumn.name,
              newTimestamp,
              isFromServer: options.isFromServer,
            );
          }
        }
      }
    }
    
    // Only update if there are actual changes
    if (updateValues.isNotEmpty) {
      updateValues[SystemColumns.systemVersion] = SystemColumnUtils.generateHLCTimestamp();
      
      final table = schema.getTable(tableName)!;
      final primaryKeyColumns = table.getPrimaryKeyColumns();
      final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue, table);
      
      await txn.update(
        tableName,
        updateValues,
        where: whereClause,
        whereArgs: whereArgs,
      );
    }
  }
}