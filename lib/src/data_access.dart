import 'package:sqflite_common/sqflite.dart';
import 'package:meta/meta.dart';
import 'dart:math';
import 'dart:async';
import 'schema_builder.dart';
import 'table_builder.dart';
import 'column_builder.dart';
import 'data_types.dart';
import 'lww_types.dart';
import 'relationship_builder.dart';
import 'stream_dependency_tracker.dart';

/// A function that generates data for a stream when it needs to be refreshed
typedef StreamDataGenerator<T> = Future<T> Function();

/// A reactive stream that automatically updates when its dependencies change
class ReactiveStream<T> {
  ReactiveStream({
    required this.streamId,
    required this.dataGenerator,
    this.initialData,
    this.bufferChanges = false,
    this.debounceTime = const Duration(milliseconds: 100),
  }) : _controller = StreamController<T>.broadcast() {
    
    // Generate initial data if provided
    if (initialData != null) {
      _controller.add(initialData!);
    }
  }
  
  /// Unique identifier for this stream
  final String streamId;
  
  /// Function that generates the data for this stream
  final StreamDataGenerator<T> dataGenerator;
  
  /// Optional initial data
  final T? initialData;
  
  /// Whether to buffer rapid changes and emit only the latest
  final bool bufferChanges;
  
  /// Debounce time for buffered changes
  final Duration debounceTime;
  
  /// Internal stream controller
  final StreamController<T> _controller;
  
  /// Timer for debouncing changes
  Timer? _debounceTimer;
  
  /// Whether this stream is currently active (has listeners)
  bool get hasListeners => _controller.hasListener;
  
  /// The stream that clients listen to
  Stream<T> get stream => _controller.stream;
  
  /// Last emitted value
  T? _lastValue;
  T? get lastValue => _lastValue;
  
  /// Refreshes the stream by calling the data generator
  Future<void> refresh() async {
    if (_controller.isClosed) return;
    
    try {
      final newData = await dataGenerator();
      _lastValue = newData;
      
      if (bufferChanges) {
        _scheduleBufferedUpdate(newData);
      } else {
        _controller.add(newData);
      }
    } catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
    }
  }
  
  /// Schedules a buffered update with debouncing
  void _scheduleBufferedUpdate(T data) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceTime, () {
      if (!_controller.isClosed) {
        _controller.add(data);
      }
    });
  }
  
  /// Closes the stream and cleans up resources
  Future<void> close() async {
    _debounceTimer?.cancel();
    await _controller.close();
  }
  
  /// Whether the stream is closed
  bool get isClosed => _controller.isClosed;
}

/// Manages reactive streams with automatic dependency-based invalidation
class ReactiveStreamManager {
  ReactiveStreamManager({
    required this.dataAccess,
    required this.schema,
  }) : _dependencyTracker = StreamDependencyTracker(schema);

  final DataAccess dataAccess;
  final SchemaBuilder schema;
  final StreamDependencyTracker _dependencyTracker;
  final Map<String, ReactiveStream> _streams = {};

  /// Creates a reactive stream for table data
  ReactiveStream<List<Map<String, dynamic>>> createTableStream(
    String streamId,
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
    bool bufferChanges = true,
    Duration debounceTime = const Duration(milliseconds: 100),
  }) {
    // Create the reactive stream
    final stream = ReactiveStream<List<Map<String, dynamic>>>(
      streamId: streamId,
      dataGenerator: () => dataAccess.getAllWhere(
        tableName,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      ),
      bufferChanges: bufferChanges,
      debounceTime: debounceTime,
    );
    
    // Register dependencies
    _dependencyTracker.registerStream(
      streamId,
      tableName,
      where: where,
      whereArgs: whereArgs,
    );
    
    // Store the stream
    _streams[streamId] = stream;
    
    // Generate initial data asynchronously
    Future.microtask(() => stream.refresh());
    
    return stream;
  }

  /// Creates a reactive stream for aggregated data
  ReactiveStream<T> createAggregateStream<T>(
    String streamId,
    String tableName,
    StreamDataGenerator<T> aggregateFunction, {
    String? where,
    List<dynamic>? whereArgs,
    List<String>? dependentColumns,
    bool bufferChanges = true,
    Duration debounceTime = const Duration(milliseconds: 100),
  }) {
    // Create the reactive stream
    final stream = ReactiveStream<T>(
      streamId: streamId,
      dataGenerator: aggregateFunction,
      bufferChanges: bufferChanges,
      debounceTime: debounceTime,
    );
    
    // Register dependencies
    _dependencyTracker.registerStream(
      streamId,
      tableName,
      where: where,
      whereArgs: whereArgs,
      columns: dependentColumns,
    );
    
    // Store the stream
    _streams[streamId] = stream;
    
    // Generate initial data asynchronously
    Future.microtask(() => stream.refresh());
    
    return stream;
  }

  /// Creates a reactive stream for raw SQL queries
  ReactiveStream<List<Map<String, dynamic>>> createRawQueryStream(
    String streamId,
    String query,
    List<dynamic>? arguments, {
    bool bufferChanges = true,
    Duration debounceTime = const Duration(milliseconds: 100),
  }) {
    // Create the reactive stream
    final stream = ReactiveStream<List<Map<String, dynamic>>>(
      streamId: streamId,
      dataGenerator: () => dataAccess.database.rawQuery(query, arguments),
      bufferChanges: bufferChanges,
      debounceTime: debounceTime,
    );
    
    // Register dependencies based on query analysis
    // For now, use a conservative approach and register dependency on all tables
    // TODO: Implement proper query parsing to determine specific table dependencies
    final allTables = schema.tables.map((table) => table.name).toList();
    if (allTables.isNotEmpty) {
      _dependencyTracker.registerStream(streamId, allTables.first);
    }
    
    // Store the stream
    _streams[streamId] = stream;
    
    // Generate initial data asynchronously
    Future.microtask(() => stream.refresh());
    
    return stream;
  }
  
  /// Notifies the manager about a database change
  Future<void> notifyChange(DatabaseChange change) async {
    // Get affected streams
    final affectedStreams = _dependencyTracker.getAffectedStreams(change);
    
    // Refresh affected streams
    final refreshFutures = <Future<void>>[];
    for (final streamId in affectedStreams) {
      final stream = _streams[streamId];
      if (stream != null && stream.hasListeners && !stream.isClosed) {
        refreshFutures.add(stream.refresh());
      }
    }
    
    // Wait for all refreshes to complete
    await Future.wait(refreshFutures);
  }
  
  /// Removes a stream and cleans up its dependencies
  Future<void> removeStream(String streamId) async {
    final stream = _streams.remove(streamId);
    if (stream != null) {
      await stream.close();
    }
    
    _dependencyTracker.unregisterStream(streamId);
  }
  
  /// Gets a stream by ID
  ReactiveStream? getStream(String streamId) {
    return _streams[streamId];
  }
  
  /// Gets all active stream IDs
  Set<String> get activeStreams => _streams.keys.toSet();
  
  /// Gets dependency statistics
  DependencyStats getDependencyStats() {
    return _dependencyTracker.getStats();
  }
  
  /// Cleans up inactive streams (streams with no listeners)
  Future<void> cleanupInactiveStreams() async {
    final inactiveStreams = <String>[];
    
    for (final entry in _streams.entries) {
      if (!entry.value.hasListeners || entry.value.isClosed) {
        inactiveStreams.add(entry.key);
      }
    }
    
    for (final streamId in inactiveStreams) {
      await removeStream(streamId);
    }
  }
  
  /// Disposes all streams and cleans up resources
  Future<void> dispose() async {
    final disposeFutures = _streams.values.map((stream) => stream.close()).toList();
    await Future.wait(disposeFutures);
    _streams.clear();
  }
}

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
  });

  /// Creates a DataAccess instance with automatic LWW support detection
  /// 
  /// [database] The SQLite database instance
  /// [schema] The schema definition containing table metadata
  /// 
  /// LWW (Last-Writer-Wins) conflict resolution is automatically enabled
  /// if any columns in the schema are marked with `.lww()`.
  static Future<DataAccess> create({
    required Database database,
    required SchemaBuilder schema,
  }) async {
    final instance = DataAccess._(
      database: database,
      schema: schema,
    );
    
    // Check if any table has LWW columns and initialize if needed
    if (instance._hasAnyLWWColumns()) {
      await instance._initializeLWWTables();
    }
    
    // Initialize reactive functionality
    instance._streamManager = ReactiveStreamManager(
      dataAccess: instance,
      schema: schema,
    );
    
    // Start auto-cleanup timer for inactive streams
    instance._autoCleanupTimer = Timer.periodic(_defaultAutoCleanupInterval, (_) {
      instance._streamManager.cleanupInactiveStreams();
    });
    
    return instance;
  }

  /// The SQLite database instance
  final Database database;
  
  /// The schema definition containing table metadata
  final SchemaBuilder schema;
  
  /// Name of the internal table that stores LWW column timestamps
  static const String _lwwTimestampsTable = '_lww_column_timestamps';

  /// In-memory cache of current LWW column values
  /// Map of tableName -> primaryKey -> columnName -> LWWColumnValue
  final Map<String, Map<dynamic, Map<String, LWWColumnValue>>> _lwwCache = {};
  
  /// Queue of pending operations waiting to be synced to server
  final Map<String, PendingOperation> _pendingOperations = {};

  /// Reactive stream manager for change notifications and dependency tracking
  late final ReactiveStreamManager _streamManager;
  
  /// Timer for automatic cleanup of inactive streams
  Timer? _autoCleanupTimer;
  
  /// Auto-cleanup interval for inactive streams
  static const Duration _defaultAutoCleanupInterval = Duration(minutes: 5);

  /// Checks if the schema contains any tables with LWW columns
  bool _hasAnyLWWColumns() {
    return schema.tables.any((table) => 
      table.columns.any((column) => column.isLWW)
    );
  }

  /// Checks if a specific table has LWW columns
  bool _hasLWWColumns(String tableName) {
    final table = schema.getTable(tableName);
    if (table == null) return false;
    return table.columns.any((column) => column.isLWW);
  }

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
    
    final result = await database.insert(tableName, processedValues);
    
    // Notify reactive streams about the change
    await _streamManager.notifyChange(DatabaseChange(
      tableName: tableName,
      operation: DatabaseOperation.insert,
      affectedColumns: processedValues.keys.toSet(),
      newValues: processedValues,
    ));
    
    return result;
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
    
    // Get old values for reactive change notification
    final oldRow = await getByPrimaryKey(tableName, primaryKeyValue);
    
    // Encode date columns and update system version
    var processedValues = DataTypeUtils.encodeRow(values, metadata.columns);
    processedValues[SystemColumns.systemVersion] = SystemColumnUtils.generateHLCTimestamp();
    
    _validateUpdateValues(table, processedValues);
    
    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue, table);
    
    final result = await database.update(
      tableName,
      processedValues,
      where: whereClause,
      whereArgs: whereArgs,
    );
    
    // Notify reactive streams about the change
    await _streamManager.notifyChange(DatabaseChange(
      tableName: tableName,
      operation: DatabaseOperation.update,
      affectedColumns: processedValues.keys.toSet(),
      primaryKeyValue: primaryKeyValue,
      oldValues: oldRow,
      newValues: processedValues,
    ));
    
    return result;
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
    if (lwwColumns.isNotEmpty) {
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
            
            // Get LWW timestamps for this row if LWW columns exist
            Map<String, String>? rowLwwTimestamps;
            if (lwwColumns.isNotEmpty && options.lwwTimestamps != null) {
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
    if (lwwColumns.isEmpty) return;
    
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
    if (lwwTimestamps != null && lwwColumns.isNotEmpty) {
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
    if (lwwTimestamps != null) {
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
    if (!_hasAnyLWWColumns()) return;
    
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
    if (!_hasLWWColumns(tableName)) return;
    
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
    if (!_hasLWWColumns(tableName)) return;
    
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
    if (!_hasLWWColumns(tableName)) return null;
    
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
  /// Returns the effective value after conflict resolution (may be different from input if rejected)
  Future<dynamic> updateLWWColumn(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
    dynamic value, {
    String? timestamp,
    String? explicitTimestamp,
    bool isFromServer = false,
  }) async {
    if (!_hasLWWColumns(tableName)) {
      throw StateError('Table "$tableName" has no LWW columns. Mark columns with .lww() in the schema definition.');
    }

    // Use explicitTimestamp if provided, then timestamp, then generate new one
    final actualTimestamp = explicitTimestamp ?? timestamp ?? SystemColumnUtils.generateHLCTimestamp();
    final table = _getTableOrThrow(tableName);
    
    // Check if column is LWW-enabled
    final column = table.columns.firstWhere(
      (col) => col.name == columnName,
      orElse: () => throw ArgumentError('Column "$columnName" not found in table "$tableName"'),
    );

    if (!column.isLWW) {
      throw ArgumentError('Column "$columnName" is not marked as LWW (.lww())');
    }

    // CRITICAL FIX: Check existing timestamp for conflict resolution
    final currentTimestamp = await _getLWWTimestamp(tableName, primaryKeyValue, columnName);
    
    // Only update if the new timestamp is newer or equal (Last-Writer-Wins)
    bool shouldUpdate = true;
    if (currentTimestamp != null) {
      shouldUpdate = actualTimestamp.compareTo(currentTimestamp) >= 0;
    }
    
    // If update should be rejected due to older timestamp, return current value
    if (!shouldUpdate) {
      return await getLWWColumnValue(tableName, primaryKeyValue, columnName);
    }

    final lwwValue = LWWColumnValue(
      value: value,
      timestamp: actualTimestamp,
      columnName: columnName,
      isFromServer: isFromServer,
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
      isFromServer: isFromServer,
    );

    // Update the actual table with the new value
    await updateByPrimaryKey(tableName, primaryKeyValue, {columnName: value});

    // Add to pending operations queue (only if not from server)
    if (!isFromServer) {
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
    
    // Return the value that was actually set
    return value;
  }

  /// Gets the current effective value of an LWW column
  Future<dynamic> getLWWColumnValue(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
  ) async {
    if (!_hasLWWColumns(tableName)) {
      throw StateError('Table "$tableName" has no LWW columns. Mark columns with .lww() in the schema definition.');
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

  /// Gets a complete row with LWW column values resolved
  /// Returns null if the row doesn't exist
  Future<Map<String, dynamic>?> getLWWRow(
    String tableName,
    dynamic primaryKeyValue,
  ) async {
    if (!_hasLWWColumns(tableName)) {
      throw StateError('Table "$tableName" has no LWW columns. Mark columns with .lww() in the schema definition.');
    }

    // Get the base row from database
    final row = await getByPrimaryKey(tableName, primaryKeyValue);
    if (row == null) return null;

    // Get table metadata to identify LWW columns
    final table = _getTableOrThrow(tableName);
    final lwwColumns = table.columns.where((col) => col.isLWW).toList();

    // Create a copy of the row to modify
    final resultRow = Map<String, dynamic>.from(row);

    // Replace LWW column values with cached values if available
    for (final lwwColumn in lwwColumns) {
      final cachedValue = _lwwCache[tableName]?[primaryKeyValue]?[lwwColumn.name];
      if (cachedValue != null) {
        resultRow[lwwColumn.name] = cachedValue.value;
      }
    }

    return resultRow;
  }

  /// Applies server update with conflict resolution
  /// Returns the effective values after conflict resolution
  Future<Map<String, dynamic>> applyServerUpdate(
    String tableName,
    dynamic primaryKeyValue,
    Map<String, dynamic> serverData,
    String serverTimestamp,
  ) async {
    if (!_hasLWWColumns(tableName)) {
      throw StateError('Table "$tableName" has no LWW columns. Mark columns with .lww() in the schema definition.');
    }

    final effectiveValues = <String, dynamic>{};

    await database.transaction((txn) async {
      for (final entry in serverData.entries) {
        final columnName = entry.key;
        final newValue = entry.value;

        // Get current timestamp for this column using transaction-safe method
        final currentTimestamp = await _getLWWTimestampTxn(
          txn,
          tableName,
          primaryKeyValue,
          columnName,
        );

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

          await _storeLWWTimestampTxn(
            txn,
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

          effectiveValues[columnName] = newValue;
        } else {
          // Local timestamp is newer, local value wins - get from cache or database
          final cachedValue = _lwwCache[tableName]?[primaryKeyValue]?[columnName];
          if (cachedValue != null) {
            effectiveValues[columnName] = cachedValue.value;
          } else {
            // Get current value from database within the same transaction
            final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(
              _getTableOrThrow(tableName).getPrimaryKeyColumns(),
              primaryKeyValue,
              _getTableOrThrow(tableName),
            );
            final result = await txn.query(
              tableName,
              columns: [columnName],
              where: whereClause,
              whereArgs: whereArgs,
              limit: 1,
            );
            effectiveValues[columnName] = result.isNotEmpty ? result.first[columnName] : null;
          }
        }
      }
    });

    return effectiveValues;
  }

  /// Gets the current timestamp for an LWW column
  Future<String?> _getLWWTimestamp(
    String tableName,
    dynamic primaryKeyValue,
    String columnName,
  ) async {
    if (!_hasLWWColumns(tableName)) return null;
    
    final serializedPrimaryKey = _serializePrimaryKey(tableName, primaryKeyValue);
    final result = await database.query(
      _lwwTimestampsTable,
      columns: ['timestamp'],
      where: 'table_name = ? AND primary_key_value = ? AND column_name = ?',
      whereArgs: [tableName, serializedPrimaryKey, columnName],
    );
    
    return result.isNotEmpty ? result.first['timestamp'] as String? : null;
  }

  /// Gets all unsynced pending operations waiting for server sync
  List<PendingOperation> getPendingOperations() {
    return _pendingOperations.values.where((op) => !op.isSynced).toList();
  }

  /// Marks an operation as synced (but keeps it for clearing later)
  void markOperationSynced(String operationId) {
    final operation = _pendingOperations[operationId];
    if (operation != null) {
      _pendingOperations[operationId] = PendingOperation(
        id: operation.id,
        tableName: operation.tableName,
        operationType: operation.operationType,
        primaryKeyValue: operation.primaryKeyValue,
        columnUpdates: operation.columnUpdates,
        timestamp: operation.timestamp,
        isSynced: true, // Mark as synced
      );
    }
  }

  /// Clears all synced operations from the pending queue
  void clearSyncedOperations() {
    _pendingOperations.removeWhere((key, operation) => operation.isSynced);
  }

  /// Clears all pending operations (useful for testing)
  void clearAllOperations() {
    _pendingOperations.clear();
  }

  // ============= Relationship Support =============

  /// Gets all child records for a parent record following a relationship
  /// 
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table  
  /// [parentValue] Value of the parent key (typically the parent record's primary key)
  /// [junctionTable] Junction table name for many-to-many relationships (optional)
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Optional limit on number of results
  /// 
  /// Returns list of child records as Maps
  Future<List<Map<String, dynamic>>> getRelated(
    String parentTable,
    String childTable,
    dynamic parentValue, {
    String? junctionTable,
    String? orderBy,
    int? limit,
  }) async {
    final relationship = schema.getRelationship(parentTable, childTable, junctionTable: junctionTable);
    if (relationship == null) {
      throw ArgumentError('No relationship found between "$parentTable" and "$childTable"');
    }

    switch (relationship.type) {
      case RelationshipType.oneToMany:
        return await _getOneToManyRelated(relationship, parentValue, orderBy: orderBy, limit: limit);
      case RelationshipType.manyToMany:
        return await _getManyToManyRelated(relationship, parentValue, orderBy: orderBy, limit: limit);
    }
  }

  /// Gets related records following a specific path through multiple tables
  /// 
  /// [path] Array of table names defining the relationship path to follow
  /// [rootValue] Value of the root record's key
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Optional limit on number of results
  /// 
  /// Example: 
  /// - `getRelatedByPath(['users', 'posts', 'comments'], userId)` gets all comments on a user's posts
  /// - `getRelatedByPath(['users', 'comments'], userId)` gets all comments made by a user directly
  /// 
  /// Returns list of target records as Maps
  Future<List<Map<String, dynamic>>> getRelatedByPath(
    List<String> path,
    dynamic rootValue, {
    String? orderBy,
    int? limit,
  }) async {
    if (path.length < 2) {
      throw ArgumentError('Path must contain at least 2 tables');
    }

    final targetTable = path.last;
    
    // Build the relationship path
    final relationshipPath = <RelationshipBuilder>[];
    for (int i = 0; i < path.length - 1; i++) {
      final parentTable = path[i];
      final childTable = path[i + 1];
      
      final relationship = schema.getRelationship(parentTable, childTable);
      if (relationship == null) {
        throw ArgumentError('No relationship found between "$parentTable" and "$childTable" in path');
      }
      
      relationshipPath.add(relationship);
    }

    // Build the nested EXISTS query for path navigation
    final pathQuery = _buildNestedExistsPathQuery(relationshipPath, targetTable, rootValue);
    if (pathQuery.sql.isEmpty) {
      return [];
    }

    var sql = pathQuery.sql;
    if (orderBy != null) {
      sql += ' ORDER BY $orderBy';
    }
    if (limit != null) {
      sql += ' LIMIT $limit';
    }

    final results = await database.rawQuery(sql, pathQuery.parameters);
    
    // Decode results using table metadata
    final table = schema.getTable(targetTable);
    if (table != null) {
      final metadata = getTableMetadata(targetTable);
      return results.map((row) => DataTypeUtils.decodeRow(row, metadata.columns)).toList();
    }
    
    return results;
  }

  /// Gets all parent records for a child record following a relationship
  /// 
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table
  /// [childValue] Value of the child key
  /// [junctionTable] Junction table name for many-to-many relationships (optional)
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Optional limit on number of results
  /// 
  /// Returns list of parent records as Maps
  Future<List<Map<String, dynamic>>> getRelatedParents(
    String parentTable,
    String childTable,
    dynamic childValue, {
    String? junctionTable,
    String? orderBy,
    int? limit,
  }) async {
    final relationship = schema.getRelationship(parentTable, childTable, junctionTable: junctionTable);
    if (relationship == null) {
      throw ArgumentError('No relationship found between "$parentTable" and "$childTable"');
    }

    switch (relationship.type) {
      case RelationshipType.oneToMany:
        // For one-to-many, get the single parent
        final parent = await getAllWhere(
          relationship.parentTable,
          where: relationship.getParentWhereCondition(),
          whereArgs: [childValue],
          orderBy: orderBy,
          limit: limit,
        );
        return parent;
      case RelationshipType.manyToMany:
        return await _getManyToManyParents(relationship, childValue, orderBy: orderBy, limit: limit);
    }
  }

  /// Deletes a record and all its children following relationship cascade rules
  /// 
  /// Uses optimized SQL with nested WHERE EXISTS and depth-first traversal to minimize database round trips.
  /// Generates O(n) queries where n is the number of tables in hierarchy - one DELETE per table.
  /// 
  /// [tableName] Name of the table containing the parent record
  /// [primaryKeyValue] Primary key value of the record to delete
  /// [force] If true, ignores restrict cascade actions and deletes anyway
  /// 
  /// Returns total number of records deleted across all tables
  Future<int> deleteWithChildren(
    String tableName,
    dynamic primaryKeyValue, {
    bool force = false,
  }) async {
    return await database.transaction((txn) async {
      // Build dependency graph and deletion order using depth-first traversal
      final deletionOrder = _buildDeletionOrder(tableName);
      
      int totalDeleted = 0;
      
      // Check for restrict cascade violations before doing any deletes
      if (!force) {
        for (final tableToDelete in deletionOrder) {
          if (tableToDelete != tableName) {
            // Check if there are any records to delete with restrict cascade
            final restrictCount = await _countRestrictCascadeViolations(txn, tableName, primaryKeyValue, tableToDelete);
            if (restrictCount > 0) {
              throw StateError('Cannot delete record from "$tableName" because it would violate cascade restrictions in "$tableToDelete"');
            }
          }
        }
      }
      
      // Delete in depth-first order (children before parents)
      for (final tableToDelete in deletionOrder) {
        final deleteCount = await _deleteRecordsWithNestedExists(
          txn, tableToDelete, tableName, primaryKeyValue
        );
        totalDeleted += deleteCount;
      }

      return totalDeleted;
    });
  }

  /// Creates a link in a many-to-many relationship
  /// 
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table
  /// [junctionTable] Name of the junction table
  /// [parentValue] Value of the parent record's key
  /// [childValue] Value of the child record's key
  Future<void> linkManyToMany(
    String parentTable,
    String childTable,
    String junctionTable,
    dynamic parentValue,
    dynamic childValue,
  ) async {
    final relationship = schema.getRelationship(parentTable, childTable, junctionTable: junctionTable);
    if (relationship == null) {
      throw ArgumentError('No many-to-many relationship found between "$parentTable" and "$childTable" via "$junctionTable"');
    }

    if (relationship.type != RelationshipType.manyToMany) {
      throw ArgumentError('Relationship between "$parentTable" and "$childTable" is not a many-to-many relationship');
    }

    final junctionParentColumn = relationship.junctionParentColumns!.first;
    final junctionChildColumn = relationship.junctionChildColumns!.first;

    await insert(junctionTable, {
      junctionParentColumn: parentValue,
      junctionChildColumn: childValue,
    });
  }

  /// Removes a link in a many-to-many relationship
  /// 
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table
  /// [junctionTable] Name of the junction table
  /// [parentValue] Value of the parent record's key
  /// [childValue] Value of the child record's key
  Future<int> unlinkManyToMany(
    String parentTable,
    String childTable,
    String junctionTable,
    dynamic parentValue,
    dynamic childValue,
  ) async {
    final relationship = schema.getRelationship(parentTable, childTable, junctionTable: junctionTable);
    if (relationship == null) {
      throw ArgumentError('No many-to-many relationship found between "$parentTable" and "$childTable" via "$junctionTable"');
    }

    if (relationship.type != RelationshipType.manyToMany) {
      throw ArgumentError('Relationship between "$parentTable" and "$childTable" is not a many-to-many relationship');
    }

    final junctionParentColumn = relationship.junctionParentColumns!.first;
    final junctionChildColumn = relationship.junctionChildColumns!.first;

    return await deleteWhere(
      junctionTable,
      where: '$junctionParentColumn = ? AND $junctionChildColumn = ?',
      whereArgs: [parentValue, childValue],
    );
  }

  // ============= Private Relationship Helper Methods =============

  /// Builds the deletion order for cascading deletes using depth-first traversal
  /// Returns list of table names in the order they should be processed for deletion
  List<String> _buildDeletionOrder(String rootTable) {
    final order = <String>[];
    final visited = <String>{};
    
    void depthFirstTraversal(String tableName) {
      if (visited.contains(tableName)) {
        return; // Prevent infinite recursion
      }
      
      visited.add(tableName);
      
      // Get all child relationships from this table
      final childRelationships = schema.getParentRelationships(tableName);
      
      // Visit all children first (depth-first)
      for (final relationship in childRelationships) {
        if (relationship.onDelete == CascadeAction.cascade || relationship.onDelete == CascadeAction.restrict) {
          depthFirstTraversal(relationship.childTable);
        }
      }
      
      // Add this table to deletion order after processing all children
      if (!order.contains(tableName)) {
        order.add(tableName);
      }
    }
    
    depthFirstTraversal(rootTable);
    return order;
  }

  /// Counts records that would violate restrict cascade rules
  Future<int> _countRestrictCascadeViolations(
    Transaction txn,
    String rootTable,
    dynamic rootPrimaryKey,
    String tableToCheck,
  ) async {
    if (tableToCheck == rootTable) {
      return 0; // Root table is not a violation
    }

    // Find the relationship path from root to this table
    final pathToTable = _findDeletionPath(rootTable, tableToCheck);
    if (pathToTable.isEmpty) {
      return 0; // No relationship path
    }

    // Check if any relationship in the path has restrict cascade
    final hasRestrict = pathToTable.any((r) => r.onDelete == CascadeAction.restrict);
    if (!hasRestrict) {
      return 0; // No restrict cascade in this path
    }

    // Count records that would be affected
    final countQuery = _buildNestedExistsCountQuery(pathToTable, rootPrimaryKey);
    final result = await txn.rawQuery(countQuery.sql, countQuery.parameters);
    return (result.first['count'] as int?) ?? 0;
  }

  /// Deletes records using a nested WHERE EXISTS approach
  Future<int> _deleteRecordsWithNestedExists(
    Transaction txn,
    String tableToDelete,
    String rootTable,
    dynamic rootPrimaryKey,
  ) async {
    if (tableToDelete == rootTable) {
      // Delete the root record itself
      return await _deleteRootRecord(txn, rootTable, rootPrimaryKey);
    }

    // Find the relationship path from root to this table
    final pathToTable = _findDeletionPath(rootTable, tableToDelete);
    if (pathToTable.isEmpty) {
      return 0; // No path found, nothing to delete
    }

    // Build the nested EXISTS DELETE query
    final deleteQuery = _buildNestedExistsDeleteQuery(pathToTable, rootPrimaryKey);
    if (deleteQuery.sql.isEmpty) {
      return 0;
    }

    // Execute the optimized DELETE query
    return await txn.rawDelete(deleteQuery.sql, deleteQuery.parameters);
  }

  /// Builds a COUNT query using nested EXISTS to count affected records
  ({String sql, List<dynamic> parameters}) _buildNestedExistsCountQuery(
    List<RelationshipBuilder> path,
    dynamic rootPrimaryKey,
  ) {
    if (path.isEmpty) {
      return (sql: '', parameters: <dynamic>[]);
    }

    final targetTable = path.last.childTable;
    final parameters = <dynamic>[rootPrimaryKey];

    // Build: SELECT COUNT(*) FROM target_table WHERE EXISTS (nested conditions)
    final sql = 'SELECT COUNT(*) as count FROM $targetTable WHERE ${_buildNestedExistsChain(path, rootPrimaryKey != null)}';
    
    return (sql: sql, parameters: parameters);
  }

  /// Builds a DELETE query using nested EXISTS pattern like user's example
  ({String sql, List<dynamic> parameters}) _buildNestedExistsDeleteQuery(
    List<RelationshipBuilder> path,
    dynamic rootPrimaryKey,
  ) {
    if (path.isEmpty) {
      return (sql: '', parameters: <dynamic>[]);
    }

    final targetTable = path.last.childTable;
    final parameters = <dynamic>[rootPrimaryKey];

    // Start building the DELETE with nested EXISTS
    final buffer = StringBuffer();
    buffer.write('DELETE FROM $targetTable WHERE ');
    
    // Build the nested EXISTS chain from the target table back to the root
    // Each EXISTS clause connects one level to the next
    buffer.write(_buildNestedExistsChain(path, rootPrimaryKey != null));
    
    return (sql: buffer.toString(), parameters: parameters);
  }

  /// Builds a nested EXISTS condition chain
  String _buildNestedExistsChain(List<RelationshipBuilder> path, bool hasRootParameter) {
    if (path.isEmpty) return '';

    final buffer = StringBuffer();
    final targetTable = path.last.childTable;
    
    // Work backwards through the path to build nested EXISTS
    for (int i = path.length - 1; i >= 0; i--) {
      final relationship = path[i];
      final isRoot = (i == 0);
      
      if (i == path.length - 1) {
        // First EXISTS: from target table to its immediate parent
        buffer.write('EXISTS (SELECT 1 FROM ${relationship.parentTable} ');
        
        if (relationship.type == RelationshipType.oneToMany) {
          buffer.write('WHERE ${relationship.parentTable}.${relationship.parentColumns.first} = $targetTable.${relationship.childColumns.first}');
        } else if (relationship.type == RelationshipType.manyToMany) {
          // For many-to-many, join through junction table
          final junctionTable = relationship.junctionTable!;
          final junctionParentCol = relationship.junctionParentColumns!.first; 
          final junctionChildCol = relationship.junctionChildColumns!.first;
          buffer.write('INNER JOIN $junctionTable ON ${relationship.parentTable}.${relationship.parentColumns.first} = $junctionTable.$junctionParentCol ');
          buffer.write('WHERE $junctionTable.$junctionChildCol = $targetTable.${relationship.childColumns.first}');
        }
      } else {
        // Subsequent nested EXISTS - connect this parent to the child from the previous level
        buffer.write(' AND EXISTS (SELECT 1 FROM ${relationship.parentTable} ');
        
        final previousRelationship = path[i + 1]; // Previous level in the chain
        
        if (relationship.type == RelationshipType.oneToMany) {
          // Connect this relationship's parent column to the previous relationship's child column
          // For example: users.id = posts.user_id (where posts.user_id comes from the previous relationship)
          buffer.write('WHERE ${relationship.parentTable}.${relationship.parentColumns.first} = ${previousRelationship.parentTable}.${relationship.childColumns.first}');
        } else if (relationship.type == RelationshipType.manyToMany) {
          final junctionTable = relationship.junctionTable!;
          final junctionParentCol = relationship.junctionParentColumns!.first;
          final junctionChildCol = relationship.junctionChildColumns!.first;
          buffer.write('INNER JOIN $junctionTable ON ${relationship.parentTable}.${relationship.parentColumns.first} = $junctionTable.$junctionParentCol ');
          buffer.write('WHERE $junctionTable.$junctionChildCol = ${previousRelationship.parentTable}.${relationship.childColumns.first}');
        }
      }
      
      // If this is the root level, add the parameter condition
      if (isRoot && hasRootParameter) {
        buffer.write(' AND ${relationship.parentTable}.${relationship.parentColumns.first} = ?');
      }
    }
    
    // Close all the EXISTS parentheses
    for (int i = 0; i < path.length; i++) {
      buffer.write(')');
    }
    
    return buffer.toString();
  }

  /// Builds a SELECT query using nested EXISTS pattern for path navigation
  ({String sql, List<dynamic> parameters}) _buildNestedExistsPathQuery(
    List<RelationshipBuilder> path,
    String targetTable,
    dynamic rootValue,
  ) {
    if (path.isEmpty) {
      return (sql: '', parameters: <dynamic>[]);
    }

    final parameters = <dynamic>[rootValue];
    
    // Build: SELECT * FROM target_table WHERE EXISTS (nested conditions)
    final sql = 'SELECT * FROM $targetTable WHERE ${_buildNestedExistsChain(path, rootValue != null)}';
    
    return (sql: sql, parameters: parameters);
  }

  /// Finds the relationship path from source table to target table
  List<RelationshipBuilder> _findDeletionPath(String sourceTable, String targetTable) {
    final visited = <String>{};
    final path = <RelationshipBuilder>[];
    
    bool findPath(String currentTable, String target, List<RelationshipBuilder> currentPath) {
      if (currentTable == target) {
        path.addAll(currentPath);
        return true;
      }
      
      if (visited.contains(currentTable)) {
        return false;
      }
      
      visited.add(currentTable);
      
      // Try all outgoing relationships
      final childRelationships = schema.getParentRelationships(currentTable);
      
      for (final relationship in childRelationships) {
        if (relationship.onDelete == CascadeAction.cascade || 
            (relationship.onDelete == CascadeAction.restrict)) {
          
          final newPath = [...currentPath, relationship];
          if (findPath(relationship.childTable, target, newPath)) {
            return true;
          }
        }
      }
      
      visited.remove(currentTable);
      return false;
    }
    
    findPath(sourceTable, targetTable, []);
    return path;
  }

  /// Deletes the root record itself
  Future<int> _deleteRootRecord(Transaction txn, String tableName, dynamic primaryKeyValue) async {
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }

    final primaryKeyColumns = table.getPrimaryKeyColumns();
    if (primaryKeyColumns.isEmpty) {
      throw ArgumentError('Table "$tableName" has no primary key');
    }

    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue, table);
    
    return await txn.delete(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  /// Gets the primary key value from a record map
  dynamic _extractPrimaryKeyValue(String tableName, Map<String, dynamic> record) {
    final table = schema.getTable(tableName);
    if (table == null) return null;

    final primaryKeys = table.getPrimaryKeyColumns();
    if (primaryKeys.isEmpty) return null;

    if (primaryKeys.length == 1) {
      return record[primaryKeys.first];
    } else {
      // For composite keys, return a map
      final keyMap = <String, dynamic>{};
      for (final keyCol in primaryKeys) {
        keyMap[keyCol] = record[keyCol];
      }
      return keyMap;
    }
  }

  /// Gets one-to-many related records
  Future<List<Map<String, dynamic>>> _getOneToManyRelated(
    RelationshipBuilder relationship,
    dynamic parentValue, {
    String? orderBy,
    int? limit,
  }) async {
    return await getAllWhere(
      relationship.childTable,
      where: relationship.getChildWhereCondition(),
      whereArgs: [parentValue],
      orderBy: orderBy,
      limit: limit,
    );
  }

  /// Gets many-to-many related records
  Future<List<Map<String, dynamic>>> _getManyToManyRelated(
    RelationshipBuilder relationship,
    dynamic parentValue, {
    String? orderBy,
    int? limit,
  }) async {
    // For many-to-many, we need to join through the junction table
    final junctionTable = relationship.junctionTable!;
    final junctionParentColumn = relationship.junctionParentColumns!.first;
    final junctionChildColumn = relationship.junctionChildColumns!.first;
    final childTable = relationship.childTable;
    final childColumn = relationship.childColumns.first;

    // Build the SQL query with JOIN
    final sql = StringBuffer();
    sql.write('SELECT $childTable.* FROM $childTable ');
    sql.write('INNER JOIN $junctionTable ON $childTable.$childColumn = $junctionTable.$junctionChildColumn ');
    sql.write('WHERE $junctionTable.$junctionParentColumn = ?');
    
    if (orderBy != null) {
      sql.write(' ORDER BY $orderBy');
    }
    if (limit != null) {
      sql.write(' LIMIT $limit');
    }

    final results = await database.rawQuery(sql.toString(), [parentValue]);
    
    // Decode results using table metadata
    final table = schema.getTable(childTable);
    if (table != null) {
      final metadata = getTableMetadata(childTable);
      return results.map((row) => DataTypeUtils.decodeRow(row, metadata.columns)).toList();
    }
    
    return results;
  }

  /// Gets many-to-many parent records
  Future<List<Map<String, dynamic>>> _getManyToManyParents(
    RelationshipBuilder relationship,
    dynamic childValue, {
    String? orderBy,
    int? limit,
  }) async {
    // For many-to-many, we need to join through the junction table
    final junctionTable = relationship.junctionTable!;
    final junctionParentColumn = relationship.junctionParentColumns!.first;
    final junctionChildColumn = relationship.junctionChildColumns!.first;
    final parentTable = relationship.parentTable;
    final parentColumn = relationship.parentColumns.first;

    // Build the SQL query with JOIN
    final sql = StringBuffer();
    sql.write('SELECT $parentTable.* FROM $parentTable ');
    sql.write('INNER JOIN $junctionTable ON $parentTable.$parentColumn = $junctionTable.$junctionParentColumn ');
    sql.write('WHERE $junctionTable.$junctionChildColumn = ?');
    
    if (orderBy != null) {
      sql.write(' ORDER BY $orderBy');
    }
    if (limit != null) {
      sql.write(' LIMIT $limit');
    }

    final results = await database.rawQuery(sql.toString(), [childValue]);
    
    // Decode results using table metadata
    final table = schema.getTable(parentTable);
    if (table != null) {
      final metadata = getTableMetadata(parentTable);
      return results.map((row) => DataTypeUtils.decodeRow(row, metadata.columns)).toList();
    }
    
    return results;
  }

  // ============= Reactive Stream Methods =============

  /// Creates a reactive stream for table data
  Stream<List<Map<String, dynamic>>> watchTable(
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
    String? streamId,
  }) {
    final id = streamId ?? 'watch_${tableName}_${DateTime.now().millisecondsSinceEpoch}';
    
    final reactiveStream = _streamManager.createTableStream(
      id,
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    
    return reactiveStream.stream;
  }

  /// Creates a reactive stream for aggregated data
  Stream<T> watchAggregate<T>(
    String tableName,
    StreamDataGenerator<T> aggregateFunction, {
    String? where,
    List<dynamic>? whereArgs,
    List<String>? dependentColumns,
    String? streamId,
  }) {
    final id = streamId ?? 'aggregate_${tableName}_${DateTime.now().millisecondsSinceEpoch}';
    
    final reactiveStream = _streamManager.createAggregateStream<T>(
      id,
      tableName,
      aggregateFunction,
      where: where,
      whereArgs: whereArgs,
      dependentColumns: dependentColumns,
    );
    
    return reactiveStream.stream;
  }

  /// Creates a reactive stream for raw SQL queries
  Stream<List<Map<String, dynamic>>> watchRawQuery(
    String query,
    List<dynamic>? arguments, {
    String? streamId,
  }) {
    final id = streamId ?? 'raw_query_${DateTime.now().millisecondsSinceEpoch}';
    
    final reactiveStream = _streamManager.createRawQueryStream(
      id,
      query,
      arguments,
    );
    
    return reactiveStream.stream;
  }

  /// Creates a reactive stream for raw aggregate queries with custom data types
  Stream<T> watchRawAggregate<T>(
    String query,
    List<dynamic>? arguments,
    T Function(List<Map<String, dynamic>>) transformer, {
    String? streamId,
  }) {
    final id = streamId ?? 'raw_aggregate_${DateTime.now().millisecondsSinceEpoch}';
    
    final reactiveStream = _streamManager.createRawQueryStream(
      id,
      query,
      arguments,
    );
    
    return reactiveStream.stream.map(transformer);
  }

  /// Creates a reactive stream for counting records
  Stream<int> watchCount(
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    String? streamId,
  }) {
    return watchAggregate<int>(
      tableName,
      () => count(tableName, where: where, whereArgs: whereArgs),
      where: where,
      whereArgs: whereArgs,
      streamId: streamId,
    );
  }

  /// Creates a reactive stream for a single record by primary key
  Stream<Map<String, dynamic>?> watchByPrimaryKey(
    String tableName,
    dynamic primaryKeyValue, {
    String? streamId,
  }) {
    final id = streamId ?? 'pk_${tableName}_${primaryKeyValue}_${DateTime.now().millisecondsSinceEpoch}';
    
    return watchAggregate<Map<String, dynamic>?>(
      tableName,
      () => getByPrimaryKey(tableName, primaryKeyValue),
      streamId: id,
    );
  }

  // ============= Pull-to-Refresh Methods =============

  /// Manually refreshes a specific stream by stream ID
  Future<void> refreshStream(String streamId) async {
    final stream = _streamManager.getStream(streamId);
    if (stream != null && !stream.isClosed) {
      await stream.refresh();
    }
  }

  /// Refreshes all streams watching a specific table (useful for pull-to-refresh)
  Future<void> refreshTable(String tableName) async {
    // Get all active streams and refresh those that might be affected by this table
    final activeStreams = _streamManager.activeStreams;
    final refreshFutures = <Future<void>>[];
    
    for (final streamId in activeStreams) {
      // For now, refresh all streams that contain the table name in their ID
      // This is a simple heuristic that works for most common patterns
      if (streamId.contains(tableName)) {
        refreshFutures.add(refreshStream(streamId));
      }
    }
    
    // If no streams match the heuristic, refresh all streams
    // This ensures pull-to-refresh always works even if naming doesn't match
    if (refreshFutures.isEmpty) {
      for (final streamId in activeStreams) {
        refreshFutures.add(refreshStream(streamId));
      }
    }
    
    await Future.wait(refreshFutures);
  }

  /// Refreshes all active streams (useful for global pull-to-refresh)
  Future<void> refreshAll() async {
    final activeStreams = _streamManager.activeStreams;
    final refreshFutures = activeStreams.map((streamId) => refreshStream(streamId));
    await Future.wait(refreshFutures);
  }

  /// Manually cleans up inactive streams
  Future<void> cleanupInactiveStreams() async {
    await _streamManager.cleanupInactiveStreams();
  }

  /// Gets dependency statistics for reactive streams
  DependencyStats getDependencyStats() {
    return _streamManager.getDependencyStats();
  }

  /// Disposes all reactive streams and cleans up resources
  Future<void> dispose() async {
    _autoCleanupTimer?.cancel();
    await _streamManager.dispose();
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