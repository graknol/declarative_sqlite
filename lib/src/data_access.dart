import 'package:sqflite_common/sqflite.dart';
import 'package:meta/meta.dart';
import 'dart:math';
import 'schema_builder.dart';
import 'table_builder.dart';
import 'column_builder.dart';
import 'data_types.dart';
import 'lww_types.dart';

/// Utilities for generating system column values
class SystemColumnUtils {
  static final Random _random = Random();
  
  /// Generates a GUID v4 string
  static String generateGuid() {
    final bytes = List<int>.generate(16, (i) => _random.nextInt(256));
    
    // Set version (4) and variant bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 10
    
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
  
  /// Generates a hybrid logical clock (HLC) timestamp string
  /// For now, using a simple timestamp with microsecond precision
  /// In a full implementation, this would include logical clock components
  static String generateHLCTimestamp() {
    final now = DateTime.now().toUtc();
    final timestamp = now.microsecondsSinceEpoch;
    return timestamp.toString();
  }
  
  /// Adds system column values to a row map if they don't already exist
  static Map<String, dynamic> ensureSystemColumns(Map<String, dynamic> values, {String? existingSystemId}) {
    final result = Map<String, dynamic>.from(values);
    
    // Add systemId if not provided
    if (!result.containsKey(SystemColumns.systemId)) {
      result[SystemColumns.systemId] = existingSystemId ?? generateGuid();
    }
    
    // Always update systemVersion on modifications
    result[SystemColumns.systemVersion] = generateHLCTimestamp();
    
    return result;
  }
}

/// Utilities for handling data type conversions, especially for Date columns
class DataTypeUtils {
  /// Encodes a value for storage based on the column's data type
  static dynamic encodeValue(dynamic value, SqliteDataType dataType) {
    if (value == null) return null;
    
    switch (dataType) {
      case SqliteDataType.date:
        if (value is DateTime) {
          return value.toUtc().toIso8601String();
        } else if (value is String) {
          // Try to parse and re-encode to ensure valid format
          try {
            final dateTime = DateTime.parse(value);
            return dateTime.toUtc().toIso8601String();
          } catch (e) {
            throw ArgumentError('Invalid date format: $value. Expected ISO8601 format or DateTime object.');
          }
        } else {
          throw ArgumentError('Date column expects DateTime or ISO8601 string, got ${value.runtimeType}');
        }
      default:
        return value;
    }
  }
  
  /// Decodes a value from storage based on the column's data type
  static dynamic decodeValue(dynamic value, SqliteDataType dataType) {
    if (value == null) return null;
    
    switch (dataType) {
      case SqliteDataType.date:
        if (value is String) {
          try {
            return DateTime.parse(value);
          } catch (e) {
            throw ArgumentError('Invalid stored date format: $value');
          }
        }
        return value;
      default:
        return value;
    }
  }
  
  /// Encodes a full row map based on table metadata
  static Map<String, dynamic> encodeRow(Map<String, dynamic> row, Map<String, ColumnBuilder> columnMetadata) {
    final encoded = <String, dynamic>{};
    
    for (final entry in row.entries) {
      final columnMeta = columnMetadata[entry.key];
      if (columnMeta != null) {
        encoded[entry.key] = encodeValue(entry.value, columnMeta.dataType);
      } else {
        encoded[entry.key] = entry.value;
      }
    }
    
    return encoded;
  }
  
  /// Decodes a full row map based on table metadata
  static Map<String, dynamic> decodeRow(Map<String, dynamic> row, Map<String, ColumnBuilder> columnMetadata) {
    final decoded = <String, dynamic>{};
    
    for (final entry in row.entries) {
      final columnMeta = columnMetadata[entry.key];
      if (columnMeta != null) {
        decoded[entry.key] = decodeValue(entry.value, columnMeta.dataType);
      } else {
        decoded[entry.key] = entry.value;
      }
    }
    
    return decoded;
  }
}

/// A comprehensive data access layer that provides type-safe database operations
/// with support for CRUD operations, bulk loading, LWW conflict resolution,
/// and relationship management.
/// 
/// This class uses the schema definition to provide type-safe database operations
/// with automatic primary key handling and constraint validation.
class DataAccess {
  /// Private constructor to ensure proper initialization through factory methods
  DataAccess._({
    required this.database,
    required this.schema,
    required this.lwwEnabled,
  });

  /// Creates a basic DataAccess instance without LWW support
  factory DataAccess({
    required Database database,
    required SchemaBuilder schema,
  }) {
    return DataAccess._(
      database: database,
      schema: schema,
      lwwEnabled: false,
    );
  }

  /// Creates a DataAccess instance with LWW support enabled
  /// Initializes the LWW metadata tables automatically
  static Future<DataAccess> createWithLWW({
    required Database database,
    required SchemaBuilder schema,
  }) async {
    final instance = DataAccess._(
      database: database,
      schema: schema,
      lwwEnabled: true,
    );
    await instance._initializeLWWTables();
    return instance;
  }

  /// The SQLite database instance
  final Database database;
  
  /// The schema definition containing table metadata
  final SchemaBuilder schema;
  
  /// Whether LWW functionality is enabled for this instance
  final bool lwwEnabled;
  
  /// Name of the internal table that stores LWW column timestamps
  static const String _lwwTimestampsTable = '_lww_column_timestamps';

  /// In-memory cache of current LWW column values
  /// Map of tableName -> primaryKey -> columnName -> LWWColumnValue
  final Map<String, Map<dynamic, Map<String, LWWColumnValue>>> _lwwCache = {};
  
  /// Queue of pending operations waiting to be synced to server
  final Map<String, PendingOperation> _pendingOperations = {};

  /// Gets a single row by primary key from the specified table.
  /// 
  /// Returns null if no row is found with the given primary key value(s).
  /// Throws [ArgumentError] if the table doesn't exist or has no primary key.
  /// 
  /// For single primary key tables:
  /// [primaryKeyValue] should be the value of the primary key
  /// 
  /// For composite primary key tables:
  /// [primaryKeyValue] should be a Map<String, dynamic> with column names as keys
  /// or a List with values in the same order as the composite key columns
  /// 
  /// [tableName] The name of the table to query
  /// [primaryKeyValue] The primary key value(s) to search for
  Future<Map<String, dynamic>?> getByPrimaryKey(String tableName, dynamic primaryKeyValue) async {
    final table = _getTableOrThrow(tableName);
    final metadata = getTableMetadata(tableName);
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    
    if (primaryKeyColumns.isEmpty) {
      throw ArgumentError('Table "$tableName" has no primary key');
    }
    
    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue, table);
    
    final results = await database.query(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    
    // Decode date columns
    return DataTypeUtils.decodeRow(results.first, metadata.columns);
  }

  /// Gets all rows from a table that match the specified where condition.
  /// 
  /// [tableName] The name of the table to query
  /// [where] SQL WHERE clause (without the WHERE keyword)
  /// [whereArgs] Arguments to bind to the WHERE clause
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Maximum number of rows to return
  /// [offset] Number of rows to skip
  Future<List<Map<String, dynamic>>> getAllWhere(
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    _getTableOrThrow(tableName); // Validate table exists
    final metadata = getTableMetadata(tableName);
    
    final results = await database.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    
    // Decode date columns for all results
    return results.map((row) => DataTypeUtils.decodeRow(row, metadata.columns)).toList();
  }

  /// Gets all rows from a table.
  /// 
  /// [tableName] The name of the table to query
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Maximum number of rows to return
  /// [offset] Number of rows to skip
  Future<List<Map<String, dynamic>>> getAll(
    String tableName, {
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return getAllWhere(tableName, orderBy: orderBy, limit: limit, offset: offset);
  }

  /// Inserts a new row into the specified table.
  /// 
  /// Returns the rowid of the inserted row, or null if no primary key.
  /// Validates that required (NOT NULL) columns are provided unless they have defaults.
  /// Automatically populates system columns (systemId, systemVersion).
  /// 
  /// [tableName] The name of the table to insert into
  /// [values] Map of column names to values
  Future<int> insert(String tableName, Map<String, dynamic> values) async {
    final table = _getTableOrThrow(tableName);
    final metadata = getTableMetadata(tableName);
    
    // Encode date columns and add system columns
    var processedValues = DataTypeUtils.encodeRow(values, metadata.columns);
    processedValues = SystemColumnUtils.ensureSystemColumns(processedValues);
    
    _validateInsertValues(table, processedValues);
    
    return await database.insert(tableName, processedValues);
  }

  /// Updates specific columns of a row identified by primary key.
  /// 
  /// Only updates the columns specified in [values]. Other columns remain unchanged.
  /// Returns the number of rows affected (should be 0 or 1).
  /// Automatically updates systemVersion.
  /// 
  /// For single primary key tables:
  /// [primaryKeyValue] should be the value of the primary key
  /// 
  /// For composite primary key tables:
  /// [primaryKeyValue] should be a Map<String, dynamic> with column names as keys
  /// or a List with values in the same order as the composite key columns
  /// 
  /// [tableName] The name of the table to update
  /// [primaryKeyValue] The primary key value(s) of the row to update
  /// [values] Map of column names to new values (only columns to update)
  Future<int> updateByPrimaryKey(
    String tableName, 
    dynamic primaryKeyValue, 
    Map<String, dynamic> values
  ) async {
    final table = _getTableOrThrow(tableName);
    final metadata = getTableMetadata(tableName);
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    
    if (primaryKeyColumns.isEmpty) {
      throw ArgumentError('Table "$tableName" has no primary key');
    }
    
    if (values.isEmpty) {
      throw ArgumentError('At least one column value must be provided for update');
    }
    
    // Encode date columns and update system version
    var processedValues = DataTypeUtils.encodeRow(values, metadata.columns);
    processedValues[SystemColumns.systemVersion] = SystemColumnUtils.generateHLCTimestamp();
    
    _validateUpdateValues(table, processedValues);
    
    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue, table);
    
    return await database.update(
      tableName,
      processedValues,
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  /// Updates rows matching the specified where condition.
  /// 
  /// [tableName] The name of the table to update
  /// [values] Map of column names to new values
  /// [where] SQL WHERE clause (without the WHERE keyword)
  /// [whereArgs] Arguments to bind to the WHERE clause
  Future<int> updateWhere(
    String tableName,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final table = _getTableOrThrow(tableName);
    final metadata = getTableMetadata(tableName);
    
    if (values.isEmpty) {
      throw ArgumentError('At least one column value must be provided for update');
    }
    
    // Encode date columns and update system version
    var processedValues = DataTypeUtils.encodeRow(values, metadata.columns);
    processedValues[SystemColumns.systemVersion] = SystemColumnUtils.generateHLCTimestamp();
    
    _validateUpdateValues(table, processedValues);
    
    return await database.update(
      tableName,
      processedValues,
      where: where,
      whereArgs: whereArgs,
    );
  }

  /// Deletes a row by primary key.
  /// 
  /// Returns the number of rows deleted (should be 0 or 1).
  /// 
  /// For single primary key tables:
  /// [primaryKeyValue] should be the value of the primary key
  /// 
  /// For composite primary key tables:
  /// [primaryKeyValue] should be a Map<String, dynamic> with column names as keys
  /// or a List with values in the same order as the composite key columns
  /// 
  /// [tableName] The name of the table to delete from
  /// [primaryKeyValue] The primary key value(s) of the row to delete
  Future<int> deleteByPrimaryKey(String tableName, dynamic primaryKeyValue) async {
    final table = _getTableOrThrow(tableName);
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    
    if (primaryKeyColumns.isEmpty) {
      throw ArgumentError('Table "$tableName" has no primary key');
    }
    
    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue, table);
    
    return await database.delete(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  /// Deletes rows matching the specified where condition.
  /// 
  /// [tableName] The name of the table to delete from
  /// [where] SQL WHERE clause (without the WHERE keyword)
  /// [whereArgs] Arguments to bind to the WHERE clause
  Future<int> deleteWhere(
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    _getTableOrThrow(tableName); // Validate table exists
    
    return await database.delete(
      tableName,
      where: where,
      whereArgs: whereArgs,
    );
  }

  /// Counts rows in a table matching the specified condition.
  /// 
  /// [tableName] The name of the table to count
  /// [where] Optional SQL WHERE clause
  /// [whereArgs] Arguments to bind to the WHERE clause
  Future<int> count(String tableName, {String? where, List<dynamic>? whereArgs}) async {
    _getTableOrThrow(tableName); // Validate table exists
    
    final result = await database.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName${where != null ? ' WHERE $where' : ''}',
      whereArgs,
    );
    
    return result.first['count'] as int;
  }

  /// Checks if a row exists with the given primary key value.
  /// 
  /// For single primary key tables:
  /// [primaryKeyValue] should be the value of the primary key
  /// 
  /// For composite primary key tables:
  /// [primaryKeyValue] should be a Map<String, dynamic> with column names as keys
  /// or a List with values in the same order as the composite key columns
  /// 
  /// [tableName] The name of the table to check
  /// [primaryKeyValue] The primary key value(s) to look for
  Future<bool> existsByPrimaryKey(String tableName, dynamic primaryKeyValue) async {
    final table = _getTableOrThrow(tableName);
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    
    if (primaryKeyColumns.isEmpty) {
      throw ArgumentError('Table "$tableName" has no primary key');
    }
    
    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue, table);
    
    final count = await this.count(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
    );
    
    return count > 0;
  }

  /// Efficiently loads a large dataset into a table using bulk operations.
  /// 
  /// This method uses database transactions and batch operations for optimal performance.
  /// It automatically handles cases where the dataset has more or fewer columns
  /// than the database table, filtering appropriately based on the schema.
  /// 
  /// Supports both insert-only mode and upsert mode (insert new, update existing).
  /// Automatically handles date column encoding and system column population.
  /// 
  /// [tableName] The name of the table to load data into
  /// [dataset] List of maps representing rows to insert/update
  /// [options] Configuration options for the bulk load operation
  /// 
  /// Returns [BulkLoadResult] with statistics about the operation.
  /// 
  /// Throws [ArgumentError] if required columns are missing from the dataset
  /// when no default values are defined.
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
    
    final table = _getTableOrThrow(tableName);
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
    
    // LWW validation and preprocessing
    final lwwColumns = table.columns.where((col) => col.isLWW).toList();
    if (lwwEnabled && lwwColumns.isNotEmpty) {
      _validateLWWTimestamps(dataset, options, lwwColumns);
    }
    
    await database.transaction((txn) async {
      // Clear table if requested
      if (options.clearTableFirst) {
        await txn.delete(tableName);
      }
      
      final batchSize = options.batchSize;
      
      for (var i = 0; i < dataset.length; i += batchSize) {
        final batch = txn.batch();
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
            
            // Encode date columns
            final encodedRow = DataTypeUtils.encodeRow(filteredRow, metadata.columns);
            
            // Validate the encoded row data if validation is enabled
            if (options.validateData) {
              _validateInsertValues(table, encodedRow);
            }
            
            // Get LWW timestamps for this row if LWW is enabled
            Map<String, String>? rowLwwTimestamps;
            if (lwwEnabled && lwwColumns.isNotEmpty && options.lwwTimestamps != null) {
              rowLwwTimestamps = options.lwwTimestamps![j];
            }
            
            if (options.upsertMode && primaryKeyColumns.isNotEmpty) {
              // Upsert mode with potential LWW conflict resolution
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
                if (options.allowPartialData) {
                  rowsSkipped++;
                  if (options.collectErrors) {
                    errors.add('Row $j: Missing primary key values for upsert mode');
                  }
                  continue;
                } else {
                  throw ArgumentError('Row $j: Missing primary key values for upsert mode');
                }
              }
              
              // Check if row exists - use the correct parameter format
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
                // Row exists, update it with LWW conflict resolution
                await _upsertRowWithLWW(
                  txn,
                  tableName,
                  encodedRow,
                  pkValue,
                  lwwColumns,
                  rowLwwTimestamps,
                  options.isFromServer,
                );
                rowsUpdated++;
              } else {
                // Row doesn't exist, insert it
                await _insertRowWithLWW(
                  txn,
                  tableName,
                  encodedRow,
                  lwwColumns,
                  rowLwwTimestamps,
                  options.isFromServer,
                );
                rowsInserted++;
              }
            } else {
              // Insert-only mode
              await _insertRowWithLWW(
                txn,
                tableName,
                encodedRow,
                lwwColumns,
                rowLwwTimestamps,
                options.isFromServer,
              );
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
        
        await batch.commit(noResult: true);
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

  /// Gets metadata about a table from the schema.
  /// 
  /// [tableName] The name of the table
  /// Returns [TableMetadata] with column and constraint information.
  TableMetadata getTableMetadata(String tableName) {
    final table = _getTableOrThrow(tableName);
    
    // Get primary key columns (single or composite)
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    
    // Exclude system columns from required columns since they are auto-populated
    final requiredColumns = table.columns
        .where((col) => col.constraints.contains(ConstraintType.notNull) && 
                        col.defaultValue == null &&
                        !SystemColumns.isSystemColumn(col.name))
        .map((col) => col.name)
        .toList();
    
    final uniqueColumns = table.columns
        .where((col) => col.constraints.contains(ConstraintType.unique))
        .map((col) => col.name)
        .toList();
    
    return TableMetadata(
      tableName: tableName,
      columns: Map.fromEntries(
        table.columns.map((col) => MapEntry(col.name, col))
      ),
      primaryKeyColumns: primaryKeyColumns,
      requiredColumns: requiredColumns,
      uniqueColumns: uniqueColumns,
      indices: table.indices.map((idx) => idx.name).toList(),
    );
  }

  /// Gets the table builder for a table or throws if it doesn't exist.
  TableBuilder _getTableOrThrow(String tableName) {
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" does not exist in schema');
    }
    return table;
  }

  /// Builds a WHERE clause and arguments for primary key matching
  /// Returns a tuple of (whereClause, whereArgs)
  (String, List<dynamic>) _buildPrimaryKeyWhereClause(List<String> primaryKeyColumns, dynamic primaryKeyValue, [TableBuilder? table]) {
    if (primaryKeyColumns.length == 1) {
      // Single primary key
      dynamic encodedValue = primaryKeyValue;
      if (table != null) {
        final column = table.columns.firstWhere((col) => col.name == primaryKeyColumns.first);
        encodedValue = DataTypeUtils.encodeValue(primaryKeyValue, column.dataType);
      }
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
          
          dynamic encodedValue = primaryKeyValue[columnName];
          if (table != null) {
            final column = table.columns.firstWhere((col) => col.name == columnName);
            encodedValue = DataTypeUtils.encodeValue(primaryKeyValue[columnName], column.dataType);
          }
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
          
          dynamic encodedValue = primaryKeyValue[i];
          if (table != null) {
            final columnName = primaryKeyColumns[i];
            final column = table.columns.firstWhere((col) => col.name == columnName);
            encodedValue = DataTypeUtils.encodeValue(primaryKeyValue[i], column.dataType);
          }
          encodedArgs.add(encodedValue);
        }
        
        return (whereConditions.join(' AND '), encodedArgs);
      } else {
        throw ArgumentError('Composite primary key requires Map<String, dynamic> or List for primaryKeyValue, got ${primaryKeyValue.runtimeType}');
      }
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

  /// Validates that update values reference existing columns.
  void _validateUpdateValues(TableBuilder table, Map<String, dynamic> values) {
    // Validate that provided columns exist in the table
    for (final columnName in values.keys) {
      if (!table.columns.any((col) => col.name == columnName)) {
        throw ArgumentError('Column "$columnName" does not exist in table "${table.name}"');
      }
    }
  }

  // ============= LWW (Last-Writer-Wins) Support =============

  /// Validates LWW timestamps for bulk load operations
  void _validateLWWTimestamps(
    List<Map<String, dynamic>> dataset,
    BulkLoadOptions options,
    List<ColumnBuilder> lwwColumns,
  ) {
    if (!lwwEnabled) return;
    
    if (options.lwwTimestamps != null) {
      final lwwTimestamps = options.lwwTimestamps!;
      if (lwwTimestamps.length != dataset.length) {
        throw ArgumentError(
          'lwwTimestamps length (${lwwTimestamps.length}) must match '
          'dataset length (${dataset.length})'
        );
      }
      
      // Validate that each row with LWW columns has corresponding timestamps
      for (int i = 0; i < dataset.length; i++) {
        final row = dataset[i];
        final rowTimestamps = lwwTimestamps[i];
        
        for (final lwwColumn in lwwColumns) {
          if (row.containsKey(lwwColumn.name)) {
            if (rowTimestamps == null || !rowTimestamps.containsKey(lwwColumn.name)) {
              throw ArgumentError(
                'Row $i contains LWW column "${lwwColumn.name}" but no HLC timestamp provided for it in lwwTimestamps[$i]. '
                'All LWW columns must have timestamps.'
              );
            }
          }
        }
      }
    } else {
      // Check if any LWW columns are present - if so, timestamps are required
      for (final row in dataset) {
        for (final lwwColumn in lwwColumns) {
          if (row.containsKey(lwwColumn.name)) {
            throw ArgumentError(
              'Row contains LWW column "${lwwColumn.name}" but no timestamps provided. '
              'Use options.lwwTimestamps to provide HLC timestamps.'
            );
          }
        }
      }
    }
  }

  /// Inserts a row with LWW timestamp handling
  Future<void> _insertRowWithLWW(
    DatabaseExecutor txn,
    String tableName,
    Map<String, dynamic> encodedRow,
    List<ColumnBuilder> lwwColumns,
    Map<String, String>? lwwTimestamps,
    bool isFromServer,
  ) async {
    // Add system columns
    final insertValues = SystemColumnUtils.ensureSystemColumns(encodedRow);
    await txn.insert(tableName, insertValues);
    
    // Store LWW timestamps for any LWW columns present
    if (lwwEnabled && lwwTimestamps != null && lwwColumns.isNotEmpty) {
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
            lwwTimestamps.containsKey(lwwColumn.name)) {
          await _storeLWWTimestampTxn(
            txn,
            tableName,
            primaryKeyValue,
            lwwColumn.name,
            lwwTimestamps[lwwColumn.name]!,
            isFromServer: isFromServer,
          );
        }
      }
    }
  }

  /// Upserts a row with LWW conflict resolution
  Future<void> _upsertRowWithLWW(
    DatabaseExecutor txn,
    String tableName,
    Map<String, dynamic> encodedRow,
    dynamic primaryKeyValue,
    List<ColumnBuilder> lwwColumns,
    Map<String, String>? lwwTimestamps,
    bool isFromServer,
  ) async {
    final table = _getTableOrThrow(tableName);
    final primaryKeyColumns = table.getPrimaryKeyColumns();
    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue, table);
    
    // Prepare update values starting with non-LWW columns
    final updateValues = <String, dynamic>{};
    final nonLwwColumns = encodedRow.entries.where(
      (entry) => !lwwColumns.any((lwwCol) => lwwCol.name == entry.key)
    );
    
    for (final entry in nonLwwColumns) {
      updateValues[entry.key] = entry.value;
    }
    
    // Process LWW columns with conflict resolution
    if (lwwEnabled && lwwTimestamps != null) {
      for (final lwwColumn in lwwColumns) {
        if (encodedRow.containsKey(lwwColumn.name) && 
            lwwTimestamps.containsKey(lwwColumn.name)) {
          
          final newValue = encodedRow[lwwColumn.name];
          final newTimestamp = lwwTimestamps[lwwColumn.name]!;
          
          // Get current timestamp for this LWW column
          final currentTimestamp = await _getLWWTimestampTxn(
            txn,
            tableName,
            primaryKeyValue,
            lwwColumn.name,
          );
          
          bool shouldUpdate = true;
          if (currentTimestamp != null) {
            // Compare timestamps - new value wins if timestamp is newer or equal
            shouldUpdate = newTimestamp.compareTo(currentTimestamp) >= 0;
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
              isFromServer: isFromServer,
            );
          }
          // If current timestamp is newer, keep existing value (don't update)
        }
      }
    }
    
    // Update system version
    updateValues[SystemColumns.systemVersion] = SystemColumnUtils.generateHLCTimestamp();
    
    // Perform the update
    await txn.update(
      tableName,
      updateValues,
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  /// Initializes the LWW metadata table for storing per-column timestamps
  @protected
  Future<void> initializeLWWTables() async {
    if (!lwwEnabled) return;
    
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

  /// Private wrapper for initialization
  Future<void> _initializeLWWTables() async => await initializeLWWTables();

  /// Stores a timestamp for a specific LWW column
  Future<void> _storeLWWTimestamp(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
    String timestamp, {
    bool isFromServer = false,
  }) async {
    if (!lwwEnabled) return;
    
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
    if (!lwwEnabled) return;
    
    final serializedPrimaryKey = _serializePrimaryKey(tableName, primaryKeyValue);
    await txn.execute(
      '''INSERT OR REPLACE INTO $_lwwTimestampsTable 
         (table_name, primary_key_value, column_name, timestamp, is_from_server)
         VALUES (?, ?, ?, ?, ?)''',
      [tableName, serializedPrimaryKey, columnName, timestamp, isFromServer ? 1 : 0],
    );
  }

  /// Gets the current timestamp for an LWW column using transaction
  Future<String?> _getLWWTimestampTxn(
    DatabaseExecutor txn,
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
  ) async {
    if (!lwwEnabled) return null;
    
    final serializedPrimaryKey = _serializePrimaryKey(tableName, primaryKeyValue);
    final result = await txn.query(
      _lwwTimestampsTable,
      columns: ['timestamp'],
      where: 'table_name = ? AND primary_key_value = ? AND column_name = ?',
      whereArgs: [tableName, serializedPrimaryKey, columnName],
    );
    
    return result.isNotEmpty ? result.first['timestamp'] as String? : null;
  }

  /// Serializes a primary key value for storage in the LWW timestamps table
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
      // Single primary key - just convert to string
      return primaryKeyValue.toString();
    } else {
      // Composite primary key - encode each part
      final Map<String, dynamic> primaryKeyMap;
      if (primaryKeyValue is Map<String, dynamic>) {
        primaryKeyMap = primaryKeyValue;
      } else if (primaryKeyValue is List) {
        if (primaryKeyValue.length != primaryKeyColumns.length) {
          throw ArgumentError(
            'Primary key list length (${primaryKeyValue.length}) does not match '
            'number of primary key columns (${primaryKeyColumns.length})'
          );
        }
        primaryKeyMap = <String, dynamic>{};
        for (int i = 0; i < primaryKeyColumns.length; i++) {
          primaryKeyMap[primaryKeyColumns[i]] = primaryKeyValue[i];
        }
      } else {
        throw ArgumentError(
          'Composite primary key must be provided as Map<String, dynamic> or List, '
          'got ${primaryKeyValue.runtimeType}'
        );
      }

      // Create ordered JSON representation
      final orderedEntries = primaryKeyColumns.map((colName) {
        final value = primaryKeyMap[colName];
        if (value == null) {
          throw ArgumentError(
            'Primary key column "$colName" is missing from primary key value'
          );
        }
        final encodedValue = value;
        return '"$colName":${_jsonStringify(encodedValue)}';
      }).join(',');
      
      return '{$orderedEntries}';
    }
  }

  /// Helper method to stringify values for JSON
  String _jsonStringify(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"${value.replaceAll('"', '\\"')}"';
    if (value is num || value is bool) return value.toString();
    return '"$value"';
  }

  /// Updates a specific LWW column with conflict resolution
  Future<void> updateLWWColumn(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
    dynamic value, {
    String? timestamp,
  }) async {
    if (!lwwEnabled) {
      throw StateError('LWW functionality is not enabled. Use DataAccess.createWithLWW()');
    }

    final actualTimestamp = timestamp ?? SystemColumnUtils.generateHLCTimestamp();
    final table = _getTableOrThrow(tableName);
    
    // Check if column is LWW-enabled
    final column = table.columns.firstWhere(
      (col) => col.name == columnName,
      orElse: () => throw ArgumentError('Column "$columnName" not found in table "$tableName"'),
    );

    if (!column.isLWW) {
      throw ArgumentError('Column "$columnName" is not marked as LWW (.lww())');
    }

    final lwwValue = LWWColumnValue(
      value: value,
      timestamp: actualTimestamp,
      columnName: columnName,
      isFromServer: false,
    );

    // Store in cache for immediate UI feedback
    _lwwCache
        .putIfAbsent(tableName, () => {})
        .putIfAbsent(primaryKeyValue, () => {})[columnName] = lwwValue;

    // Store timestamp in database
    await _storeLWWTimestamp(
      tableName,
      primaryKeyValue,
      columnName,
      actualTimestamp,
    );

    // Update the actual table with the new value
    await updateByPrimaryKey(tableName, primaryKeyValue, {columnName: value});

    // Add to pending operations queue
    final operationId = '${SystemColumnUtils.generateGuid()}_${DateTime.now().millisecondsSinceEpoch}';
    _pendingOperations[operationId] = PendingOperation(
      id: operationId,
      tableName: tableName,
      primaryKeyValue: primaryKeyValue,
      columnUpdates: {columnName: lwwValue},
      timestamp: actualTimestamp,
      operationType: OperationType.update,
    );
  }

  /// Gets the current effective value of an LWW column
  Future<dynamic> getLWWColumnValue(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
  ) async {
    if (!lwwEnabled) {
      throw StateError('LWW functionality is not enabled. Use DataAccess.createWithLWW()');
    }

    // Check cache first
    final cachedValue = _lwwCache[tableName]?[primaryKeyValue]?[columnName];
    if (cachedValue != null) {
      return cachedValue.value;
    }

    // Fallback to database
    final row = await getByPrimaryKey(tableName, primaryKeyValue);
    return row?[columnName];
  }

  /// Applies server update with conflict resolution
  Future<void> applyServerUpdate(
    String tableName,
    dynamic primaryKeyValue,
    Map<String, dynamic> serverData,
    String serverTimestamp,
  ) async {
    if (!lwwEnabled) {
      throw StateError('LWW functionality is not enabled. Use DataAccess.createWithLWW()');
    }

    await database.transaction((txn) async {
      for (final entry in serverData.entries) {
        final columnName = entry.key;
        final newValue = entry.value;

        // Get current timestamp for this column
        final currentTimestamp = await _getLWWTimestamp(tableName, primaryKeyValue, columnName);

        // Compare timestamps - server wins if timestamp is newer or equal
        if (currentTimestamp == null || serverTimestamp.compareTo(currentTimestamp) >= 0) {
          // Server wins - update the value and timestamp
          await txn.update(
            tableName,
            {columnName: newValue},
            where: _buildPrimaryKeyWhereClause(
              _getTableOrThrow(tableName).getPrimaryKeyColumns(),
              primaryKeyValue,
              _getTableOrThrow(tableName),
            ).$1,
            whereArgs: _buildPrimaryKeyWhereClause(
              _getTableOrThrow(tableName).getPrimaryKeyColumns(),
              primaryKeyValue,
              _getTableOrThrow(tableName),
            ).$2,
          );

          await _storeLWWTimestamp(
            tableName,
            primaryKeyValue,
            columnName,
            serverTimestamp,
            isFromServer: true,
          );

          // Update cache
          _lwwCache
              .putIfAbsent(tableName, () => {})
              .putIfAbsent(primaryKeyValue, () => {})[columnName] = LWWColumnValue(
            value: newValue,
            timestamp: serverTimestamp,
            columnName: columnName,
            isFromServer: true,
          );
        }
        // If local timestamp is newer, local value wins (do nothing)
      }
    });
  }

  /// Gets the current timestamp for an LWW column
  Future<String?> _getLWWTimestamp(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
  ) async {
    if (!lwwEnabled) return null;
    
    final serializedPrimaryKey = _serializePrimaryKey(tableName, primaryKeyValue);
    final result = await database.query(
      _lwwTimestampsTable,
      columns: ['timestamp'],
      where: 'table_name = ? AND primary_key_value = ? AND column_name = ?',
      whereArgs: [tableName, serializedPrimaryKey, columnName],
    );
    
    return result.isNotEmpty ? result.first['timestamp'] as String? : null;
  }

  /// Gets all pending operations waiting for server sync
  List<PendingOperation> getPendingOperations() {
    return _pendingOperations.values.toList();
  }

  /// Marks an operation as synced and removes it from the pending queue
  void markOperationSynced(String operationId) {
    _pendingOperations.remove(operationId);
  }

  /// Clears all synced operations from the pending queue
  void clearSyncedOperations() {
    _pendingOperations.clear();
  }
}

/// Metadata information about a table derived from its schema definition.
@immutable
class TableMetadata {
  const TableMetadata({
    required this.tableName,
    required this.columns,
    required this.primaryKeyColumns,
    required this.requiredColumns,
    required this.uniqueColumns,
    required this.indices,
  });

  /// The name of the table
  final String tableName;
  
  /// Map of column name to column builder
  final Map<String, ColumnBuilder> columns;
  
  /// List of primary key column names (supports both single and composite keys)
  final List<String> primaryKeyColumns;
  
  /// List of column names that are required (NOT NULL without default)
  final List<String> requiredColumns;
  
  /// List of column names that have unique constraints
  final List<String> uniqueColumns;
  
  /// List of index names on this table
  final List<String> indices;

  /// Gets the data type of a column
  SqliteDataType? getColumnType(String columnName) {
    return columns[columnName]?.dataType;
  }

  /// Checks if a column is required (NOT NULL without default)
  bool isColumnRequired(String columnName) {
    return requiredColumns.contains(columnName);
  }

  /// Checks if a column has a unique constraint
  bool isColumnUnique(String columnName) {
    return uniqueColumns.contains(columnName);
  }

  /// Checks if a column is part of the primary key
  bool isColumnPrimaryKey(String columnName) {
    return primaryKeyColumns.contains(columnName);
  }
  
  /// Whether this table has a primary key
  bool get hasPrimaryKey => primaryKeyColumns.isNotEmpty;
  
  /// Whether this table has a composite primary key
  bool get hasCompositePrimaryKey => primaryKeyColumns.length > 1;
  
  /// Name of the primary key column (for backward compatibility - only works with single PK)
  String? get primaryKeyColumn => primaryKeyColumns.length == 1 ? primaryKeyColumns.first : null;

  @override
  String toString() {
    return 'TableMetadata(table: $tableName, columns: ${columns.length}, '
           'primaryKey: $primaryKeyColumns, required: ${requiredColumns.length})';
  }
}

/// Configuration options for bulk loading operations.
@immutable
class BulkLoadOptions {
  const BulkLoadOptions({
    this.batchSize = 1000,
    this.allowPartialData = false,
    this.validateData = true,
    this.collectErrors = false,
    this.upsertMode = false,
    this.clearTableFirst = false,
    this.lwwTimestamps,
    this.isFromServer = false,
  });

  /// Number of rows to insert in each batch (default: 1000)
  final int batchSize;
  
  /// Whether to continue processing if some rows fail validation (default: false)
  /// When true, invalid rows are skipped and reported in the result.
  final bool allowPartialData;
  
  /// Whether to validate data against schema constraints (default: true)
  final bool validateData;
  
  /// Whether to collect error messages for failed rows (default: false)
  /// Only relevant when allowPartialData is true.
  final bool collectErrors;
  
  /// Whether to use upsert mode (insert new rows, update existing ones) (default: false)
  /// When true, rows are inserted if they don't exist or updated if they do exist
  /// based on primary key matching.
  final bool upsertMode;
  
  /// Whether to clear the table before loading data (default: false)
  /// When true, all existing rows are deleted before inserting new data.
  final bool clearTableFirst;
  
  /// Per-row LWW timestamps for granular conflict resolution
  /// List where each element corresponds to a row in the dataset
  /// Each element is a Map<String, String> of column names to HLC timestamps
  /// Required for any columns marked with .lww() constraint
  final List<Map<String, String>?>? lwwTimestamps;
  
  /// Whether the data being loaded is from server (default: false)
  /// Used for LWW conflict resolution tracking
  final bool isFromServer;
}

/// Result information from a bulk load operation.
@immutable
class BulkLoadResult {
  const BulkLoadResult({
    required this.rowsProcessed,
    required this.rowsInserted,
    required this.rowsUpdated,
    required this.rowsSkipped,
    required this.errors,
  });

  /// Total number of rows processed from the dataset
  final int rowsProcessed;
  
  /// Number of rows successfully inserted
  final int rowsInserted;
  
  /// Number of rows successfully updated (only relevant in upsert mode)
  final int rowsUpdated;
  
  /// Number of rows skipped due to validation errors
  final int rowsSkipped;
  
  /// List of error messages for failed rows (if collectErrors was enabled)
  final List<String> errors;
  
  /// Whether the bulk load operation was completely successful
  bool get isComplete => rowsSkipped == 0;
  
  /// Whether the bulk load operation had any insertions
  bool get hasInsertions => rowsInserted > 0;
  
  /// Whether the bulk load operation had any updates
  bool get hasUpdates => rowsUpdated > 0;
  
  /// Total number of rows successfully processed
  int get totalSuccessful => rowsInserted + rowsUpdated;
  
  @override
  String toString() {
    return 'BulkLoadResult(processed: $rowsProcessed, inserted: $rowsInserted, '
           'updated: $rowsUpdated, skipped: $rowsSkipped, errors: ${errors.length})';
  }
}