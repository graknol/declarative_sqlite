import 'dart:async';
import 'package:meta/meta.dart';
import 'schema_builder.dart';
import 'data_access.dart';
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
  
  /// Map of stream ID to reactive stream
  final Map<String, ReactiveStream> _streams = {};
  
  /// Creates a reactive stream for a table query
  ReactiveStream<List<Map<String, dynamic>>> createTableStream(
    String streamId,
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
    List<String>? columns,
    bool bufferChanges = true,
    Duration debounceTime = const Duration(milliseconds: 100),
  }) {
    // Create the data generator function
    StreamDataGenerator<List<Map<String, dynamic>>> generator = () async {
      return await dataAccess.getAllWhere(
        tableName,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    };
    
    // Create the reactive stream
    final stream = ReactiveStream<List<Map<String, dynamic>>>(
      streamId: streamId,
      dataGenerator: generator,
      bufferChanges: bufferChanges,
      debounceTime: debounceTime,
    );
    
    // Register dependencies
    _dependencyTracker.registerStream(
      streamId,
      tableName,
      where: where,
      whereArgs: whereArgs,
      columns: columns,
      orderBy: orderBy,
    );
    
    // Store the stream
    _streams[streamId] = stream;
    
    // Generate initial data
    stream.refresh();
    
    return stream;
  }
  
  /// Creates a reactive stream for a raw SQL query
  ReactiveStream<List<Map<String, dynamic>>> createRawQueryStream(
    String streamId,
    String query,
    List<dynamic>? arguments, {
    bool bufferChanges = true,
    Duration debounceTime = const Duration(milliseconds: 100),
  }) {
    // Create the data generator function
    StreamDataGenerator<List<Map<String, dynamic>>> generator = () async {
      return await dataAccess.database.rawQuery(query, arguments);
    };
    
    // Create the reactive stream
    final stream = ReactiveStream<List<Map<String, dynamic>>>(
      streamId: streamId,
      dataGenerator: generator,
      bufferChanges: bufferChanges,
      debounceTime: debounceTime,
    );
    
    // Register dependencies by analyzing the raw query
    _dependencyTracker.registerStream(
      streamId,
      '', // Will be determined by query analysis
      rawQuery: query,
      rawQueryArgs: arguments,
    );
    
    // Store the stream
    _streams[streamId] = stream;
    
    // Generate initial data
    stream.refresh();
    
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
    
    // Generate initial data
    stream.refresh();
    
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

/// Higher-level reactive data access layer that integrates with dependency tracking
class ReactiveDataAccess {
  ReactiveDataAccess({
    required this.dataAccess,
    required this.schema,
    this.autoCleanupInterval = const Duration(minutes: 5),
  }) : _streamManager = ReactiveStreamManager(
         dataAccess: dataAccess,
         schema: schema,
       ) {
    
    // Start auto-cleanup timer
    _autoCleanupTimer = Timer.periodic(autoCleanupInterval, (_) {
      _streamManager.cleanupInactiveStreams();
    });
  }
  
  final DataAccess dataAccess;
  final SchemaBuilder schema;
  final ReactiveStreamManager _streamManager;
  final Duration autoCleanupInterval;
  
  Timer? _autoCleanupTimer;
  
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
  
  /// Creates a reactive stream for counting records
  Stream<int> watchCount(
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    String? streamId,
  }) {
    return watchAggregate<int>(
      tableName,
      () => dataAccess.count(tableName, where: where, whereArgs: whereArgs),
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
      () => dataAccess.getByPrimaryKey(tableName, primaryKeyValue),
      streamId: id,
    );
  }
  
  /// Wrapped insert operation that triggers change notifications
  Future<int> insert(String tableName, Map<String, dynamic> values) async {
    final result = await dataAccess.insert(tableName, values);
    
    // Notify change
    await _streamManager.notifyChange(DatabaseChange(
      tableName: tableName,
      operation: DatabaseOperation.insert,
      affectedColumns: values.keys.toSet(),
      newValues: values,
    ));
    
    return result;
  }
  
  /// Wrapped update operation that triggers change notifications
  Future<int> updateByPrimaryKey(
    String tableName,
    dynamic primaryKeyValue,
    Map<String, dynamic> values,
  ) async {
    // Get old values for comparison
    final oldRow = await dataAccess.getByPrimaryKey(tableName, primaryKeyValue);
    
    final result = await dataAccess.updateByPrimaryKey(tableName, primaryKeyValue, values);
    
    // Notify change
    await _streamManager.notifyChange(DatabaseChange(
      tableName: tableName,
      operation: DatabaseOperation.update,
      affectedColumns: values.keys.toSet(),
      primaryKeyValue: primaryKeyValue,
      oldValues: oldRow,
      newValues: values,
    ));
    
    return result;
  }
  
  /// Wrapped update operation that triggers change notifications
  Future<int> updateWhere(
    String tableName,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final result = await dataAccess.updateWhere(
      tableName,
      values,
      where: where,
      whereArgs: whereArgs,
    );
    
    // Notify change
    await _streamManager.notifyChange(DatabaseChange(
      tableName: tableName,
      operation: DatabaseOperation.update,
      affectedColumns: values.keys.toSet(),
      whereCondition: where,
      whereArgs: whereArgs,
      newValues: values,
    ));
    
    return result;
  }
  
  /// Wrapped delete operation that triggers change notifications
  Future<int> deleteByPrimaryKey(String tableName, dynamic primaryKeyValue) async {
    // Get old values for comparison
    final oldRow = await dataAccess.getByPrimaryKey(tableName, primaryKeyValue);
    
    final result = await dataAccess.deleteByPrimaryKey(tableName, primaryKeyValue);
    
    // Notify change
    await _streamManager.notifyChange(DatabaseChange(
      tableName: tableName,
      operation: DatabaseOperation.delete,
      affectedColumns: oldRow?.keys.toSet() ?? <String>{},
      primaryKeyValue: primaryKeyValue,
      oldValues: oldRow,
    ));
    
    return result;
  }
  
  /// Wrapped delete operation that triggers change notifications
  Future<int> deleteWhere(
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final result = await dataAccess.deleteWhere(
      tableName,
      where: where,
      whereArgs: whereArgs,
    );
    
    // Notify change
    await _streamManager.notifyChange(DatabaseChange(
      tableName: tableName,
      operation: DatabaseOperation.delete,
      affectedColumns: <String>{}, // Unknown columns for WHERE-based deletes
      whereCondition: where,
      whereArgs: whereArgs,
    ));
    
    return result;
  }
  
  /// Wrapped bulk load operation that triggers change notifications
  Future<BulkLoadResult> bulkLoad(
    String tableName,
    List<Map<String, dynamic>> dataset, {
    BulkLoadOptions options = const BulkLoadOptions(),
  }) async {
    final result = await dataAccess.bulkLoad(tableName, dataset, options: options);
    
    // Notify change for bulk operation
    final allColumns = <String>{};
    for (final row in dataset) {
      allColumns.addAll(row.keys);
    }
    
    await _streamManager.notifyChange(DatabaseChange(
      tableName: tableName,
      operation: options.upsertMode ? DatabaseOperation.bulkUpdate : DatabaseOperation.bulkInsert,
      affectedColumns: allColumns,
    ));
    
    return result;
  }
  
  /// Pass-through methods that don't modify data (no change notifications needed)
  
  Future<Map<String, dynamic>?> getByPrimaryKey(String tableName, dynamic primaryKeyValue) {
    return dataAccess.getByPrimaryKey(tableName, primaryKeyValue);
  }
  
  Future<List<Map<String, dynamic>>> getAllWhere(
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return dataAccess.getAllWhere(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }
  
  Future<List<Map<String, dynamic>>> getAll(
    String tableName, {
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return dataAccess.getAll(tableName, orderBy: orderBy, limit: limit, offset: offset);
  }
  
  Future<int> count(String tableName, {String? where, List<dynamic>? whereArgs}) {
    return dataAccess.count(tableName, where: where, whereArgs: whereArgs);
  }
  
  Future<bool> existsByPrimaryKey(String tableName, dynamic primaryKeyValue) {
    return dataAccess.existsByPrimaryKey(tableName, primaryKeyValue);
  }
  
  /// Gets dependency statistics
  DependencyStats getDependencyStats() {
    return _streamManager.getDependencyStats();
  }
  
  /// Manually refreshes a specific stream
  Future<void> refreshStream(String streamId) async {
    final stream = _streamManager.getStream(streamId);
    if (stream != null && !stream.isClosed) {
      await stream.refresh();
    }
  }
  
  /// Manually cleans up inactive streams
  Future<void> cleanupInactiveStreams() async {
    await _streamManager.cleanupInactiveStreams();
  }
  
  /// Disposes all reactive streams and cleans up resources
  Future<void> dispose() async {
    _autoCleanupTimer?.cancel();
    await _streamManager.dispose();
  }
}