import 'dart:async';
import '../builders/query_builder.dart';
import '../database.dart';
import 'query_dependency_analyzer.dart';

/// A streaming query that emits new results whenever the underlying data changes
class StreamingQuery<T> {
  final String _id;
  final QueryBuilder _builder;
  final QueryDependencies _dependencies;
  final DeclarativeDatabase _database;
  final T Function(Map<String, Object?>) _mapper;
  
  late final StreamController<List<T>> _controller;
  bool _isActive = false;
  List<T>? _lastResults;

  StreamingQuery._({
    required String id,
    required QueryBuilder builder,
    required QueryDependencies dependencies,
    required DeclarativeDatabase database,
    required T Function(Map<String, Object?>) mapper,
  })  : _id = id,
        _builder = builder,
        _dependencies = dependencies,
        _database = database,
        _mapper = mapper {
    _controller = StreamController<List<T>>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  /// Factory constructor to create a streaming query
  factory StreamingQuery.create({
    required String id,
    required QueryBuilder builder,
    required DeclarativeDatabase database,
    required T Function(Map<String, Object?>) mapper,
  }) {
    // Use schema-aware dependency analysis
    final analyzer = QueryDependencyAnalyzer(database.schema);
    final dependencies = analyzer.analyze(builder);
    return StreamingQuery._(
      id: id,
      builder: builder,
      dependencies: dependencies,
      database: database,
      mapper: mapper,
    );
  }

  /// The unique identifier for this streaming query
  String get id => _id;

  /// The dependencies this query has on database entities
  QueryDependencies get dependencies => _dependencies;

  /// The stream of query results
  Stream<List<T>> get stream => _controller.stream;

  /// Whether this query is currently active (has listeners)
  bool get isActive => _isActive;

  /// Returns true if this query might be affected by changes to the given table
  bool isAffectedByTable(String tableName) {
    return _dependencies.isAffectedByTable(tableName);
  }

  /// Returns true if this query might be affected by changes to the given column
  bool isAffectedByColumn(String tableName, String columnName) {
    return _dependencies.isAffectedByColumn(tableName, columnName);
  }

  /// Manually trigger a refresh of this query
  Future<void> refresh() async {
    if (!_isActive) return;
    
    try {
      final results = await _database.queryWith(_builder);
      final mappedResults = results.map(_mapper).toList();
      
      // Only emit if results have changed
      if (!_areResultsEqual(mappedResults, _lastResults)) {
        _lastResults = mappedResults;
        _controller.add(mappedResults);
      }
    } catch (error) {
      _controller.addError(error);
    }
  }

  /// Called when the first listener subscribes
  Future<void> _onListen() async {
    _isActive = true;
    await refresh();
  }

  /// Called when the last listener unsubscribes  
  void _onCancel() {
    _isActive = false;
    _lastResults = null;
  }

  /// Dispose of this streaming query
  void dispose() {
    _isActive = false;
    _controller.close();
  }

  /// Compare two result lists to see if they're equal
  bool _areResultsEqual(List<T>? a, List<T>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    
    return true;
  }

  @override
  String toString() {
    return 'StreamingQuery(id: $_id, dependencies: $_dependencies, active: $_isActive)';
  }
}