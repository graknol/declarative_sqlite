import 'package:sqflite_common/sqflite.dart';
import 'package:meta/meta.dart';
import 'schema_builder.dart';
import 'table_builder.dart';
import 'column_builder.dart';
import 'data_types.dart';

/// Data access abstraction layer that provides CRUD operations based on schema metadata.
/// 
/// This class uses the schema definition to provide type-safe database operations
/// with automatic primary key handling and constraint validation.
class DataAccess {
  const DataAccess({
    required this.database,
    required this.schema,
  });

  /// The SQLite database instance
  final Database database;
  
  /// The schema definition containing table metadata
  final SchemaBuilder schema;

  /// Gets a single row by primary key from the specified table.
  /// 
  /// Returns null if no row is found with the given primary key value.
  /// Throws [ArgumentError] if the table doesn't exist or has no primary key.
  /// 
  /// [tableName] The name of the table to query
  /// [primaryKeyValue] The value of the primary key to search for
  Future<Map<String, dynamic>?> getByPrimaryKey(String tableName, dynamic primaryKeyValue) async {
    final table = _getTableOrThrow(tableName);
    final primaryKeyColumn = _getPrimaryKeyColumnOrThrow(table);
    
    final results = await database.query(
      tableName,
      where: '${primaryKeyColumn.name} = ?',
      whereArgs: [primaryKeyValue],
      limit: 1,
    );
    
    return results.isEmpty ? null : results.first;
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
    
    return await database.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
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
  /// 
  /// [tableName] The name of the table to insert into
  /// [values] Map of column names to values
  Future<int> insert(String tableName, Map<String, dynamic> values) async {
    final table = _getTableOrThrow(tableName);
    _validateInsertValues(table, values);
    
    return await database.insert(tableName, values);
  }

  /// Updates specific columns of a row identified by primary key.
  /// 
  /// Only updates the columns specified in [values]. Other columns remain unchanged.
  /// Returns the number of rows affected (should be 0 or 1).
  /// 
  /// [tableName] The name of the table to update
  /// [primaryKeyValue] The primary key value of the row to update
  /// [values] Map of column names to new values (only columns to update)
  Future<int> updateByPrimaryKey(
    String tableName, 
    dynamic primaryKeyValue, 
    Map<String, dynamic> values
  ) async {
    final table = _getTableOrThrow(tableName);
    final primaryKeyColumn = _getPrimaryKeyColumnOrThrow(table);
    
    if (values.isEmpty) {
      throw ArgumentError('At least one column value must be provided for update');
    }
    
    _validateUpdateValues(table, values);
    
    return await database.update(
      tableName,
      values,
      where: '${primaryKeyColumn.name} = ?',
      whereArgs: [primaryKeyValue],
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
    
    if (values.isEmpty) {
      throw ArgumentError('At least one column value must be provided for update');
    }
    
    _validateUpdateValues(table, values);
    
    return await database.update(
      tableName,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }

  /// Deletes a row by primary key.
  /// 
  /// Returns the number of rows deleted (should be 0 or 1).
  /// 
  /// [tableName] The name of the table to delete from
  /// [primaryKeyValue] The primary key value of the row to delete
  Future<int> deleteByPrimaryKey(String tableName, dynamic primaryKeyValue) async {
    final table = _getTableOrThrow(tableName);
    final primaryKeyColumn = _getPrimaryKeyColumnOrThrow(table);
    
    return await database.delete(
      tableName,
      where: '${primaryKeyColumn.name} = ?',
      whereArgs: [primaryKeyValue],
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
  /// [tableName] The name of the table to check
  /// [primaryKeyValue] The primary key value to look for
  Future<bool> existsByPrimaryKey(String tableName, dynamic primaryKeyValue) async {
    final table = _getTableOrThrow(tableName);
    final primaryKeyColumn = _getPrimaryKeyColumnOrThrow(table);
    
    final count = await this.count(
      tableName,
      where: '${primaryKeyColumn.name} = ?',
      whereArgs: [primaryKeyValue],
    );
    
    return count > 0;
  }

  /// Efficiently loads a large dataset into a table using bulk operations.
  /// 
  /// This method uses database transactions and batch inserts for optimal performance.
  /// It automatically handles cases where the dataset has more or fewer columns
  /// than the database table, filtering appropriately based on the schema.
  /// 
  /// [tableName] The name of the table to load data into
  /// [dataset] List of maps representing rows to insert
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
        rowsSkipped: 0,
        errors: const [],
      );
    }
    
    final table = _getTableOrThrow(tableName);
    final metadata = getTableMetadata(tableName);
    
    // Analyze dataset columns vs table columns
    final datasetColumns = dataset.first.keys.toSet();
    final tableColumns = metadata.columns.keys.toSet();
    final validColumns = datasetColumns.intersection(tableColumns);
    
    final errors = <String>[];
    var rowsProcessed = 0;
    var rowsInserted = 0;
    var rowsSkipped = 0;
    
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
            
            // Validate the filtered row data if validation is enabled
            if (options.validateData) {
              _validateInsertValues(table, filteredRow);
            }
            
            batch.insert(tableName, filteredRow);
            rowsInserted++;
            
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
    
    final primaryKeyColumn = table.columns
        .where((col) => col.constraints.contains(ConstraintType.primaryKey))
        .firstOrNull;
    
    final requiredColumns = table.columns
        .where((col) => col.constraints.contains(ConstraintType.notNull) && col.defaultValue == null)
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
      primaryKeyColumn: primaryKeyColumn?.name,
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

  /// Gets the primary key column for a table or throws if none exists.
  ColumnBuilder _getPrimaryKeyColumnOrThrow(TableBuilder table) {
    final primaryKeyColumn = table.columns
        .where((col) => col.constraints.contains(ConstraintType.primaryKey))
        .firstOrNull;
    
    if (primaryKeyColumn == null) {
      throw ArgumentError('Table "${table.name}" has no primary key column');
    }
    
    return primaryKeyColumn;
  }

  /// Validates that insert values meet table constraints.
  void _validateInsertValues(TableBuilder table, Map<String, dynamic> values) {
    // Check that all NOT NULL columns without defaults are provided
    for (final column in table.columns) {
      if (column.constraints.contains(ConstraintType.notNull) && 
          column.defaultValue == null &&
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
}

/// Metadata information about a table derived from its schema definition.
@immutable
class TableMetadata {
  const TableMetadata({
    required this.tableName,
    required this.columns,
    required this.primaryKeyColumn,
    required this.requiredColumns,
    required this.uniqueColumns,
    required this.indices,
  });

  /// The name of the table
  final String tableName;
  
  /// Map of column name to column builder
  final Map<String, ColumnBuilder> columns;
  
  /// Name of the primary key column, or null if none
  final String? primaryKeyColumn;
  
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

  /// Checks if a column is the primary key
  bool isColumnPrimaryKey(String columnName) {
    return primaryKeyColumn == columnName;
  }

  @override
  String toString() {
    return 'TableMetadata(table: $tableName, columns: ${columns.length}, '
           'primaryKey: $primaryKeyColumn, required: ${requiredColumns.length})';
  }
}

/// Extension to add firstOrNull helper method
extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Configuration options for bulk loading operations.
@immutable
class BulkLoadOptions {
  const BulkLoadOptions({
    this.batchSize = 1000,
    this.allowPartialData = false,
    this.validateData = true,
    this.collectErrors = false,
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
}

/// Result information from a bulk load operation.
@immutable
class BulkLoadResult {
  const BulkLoadResult({
    required this.rowsProcessed,
    required this.rowsInserted,
    required this.rowsSkipped,
    required this.errors,
  });

  /// Total number of rows processed from the dataset
  final int rowsProcessed;
  
  /// Number of rows successfully inserted
  final int rowsInserted;
  
  /// Number of rows skipped due to validation errors
  final int rowsSkipped;
  
  /// List of error messages for failed rows (if collectErrors was enabled)
  final List<String> errors;
  
  /// Whether the bulk load operation was completely successful
  bool get isComplete => rowsSkipped == 0;
  
  /// Whether the bulk load operation had any insertions
  bool get hasInsertions => rowsInserted > 0;
  
  @override
  String toString() {
    return 'BulkLoadResult(processed: $rowsProcessed, inserted: $rowsInserted, '
           'skipped: $rowsSkipped, errors: ${errors.length})';
  }
}