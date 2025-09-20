import 'dart:async';
import 'dart:collection';
import '../builders/query_builder.dart';
import '../database.dart';
import 'query_dependency_analyzer.dart';

/// A cached result entry containing the mapped object and its hash
class _CachedResult<T> {
  final T object;
  final int hashCode;
  
  const _CachedResult(this.object, this.hashCode);
}

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
  
  /// Cache of previously mapped results indexed by their hash codes
  final Map<int, _CachedResult<T>> _resultCache = {};
  
  /// Hash codes of the last emitted result set for fast comparison
  List<int>? _lastResultHashes;

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

  /// Manually trigger a refresh of this query with hash-based optimization
  Future<void> refresh() async {
    if (!_isActive) return;
    
    try {
      final rawResults = await _database.queryWith(_builder);
      
      // Compute hash codes for all raw results
      final newResultHashes = rawResults.map(_computeRowHash).toList();
      
      // Quick check: if hash sequence is identical, no changes occurred
      if (_areHashSequencesEqual(newResultHashes, _lastResultHashes)) {
        return; // No changes, no emission needed
      }
      
      // Build the new result list using cache optimization
      final mappedResults = <T>[];
      
      for (int i = 0; i < rawResults.length; i++) {
        final rawRow = rawResults[i];
        final rowHash = newResultHashes[i];
        
        // Check if we have this row cached
        final cached = _resultCache[rowHash];
        if (cached != null) {
          // Use cached mapped object (reference equality maintained)
          mappedResults.add(cached.object);
        } else {
          // Map new row and cache it
          final mappedRow = _mapper(rawRow);
          final cachedResult = _CachedResult(mappedRow, rowHash);
          _resultCache[rowHash] = cachedResult;
          mappedResults.add(mappedRow);
        }
      }
      
      // Clean up cache: remove entries not in current result set
      _cleanupCache(newResultHashes.toSet());
      
      // Update cached state and emit
      _lastResults = mappedResults;
      _lastResultHashes = newResultHashes;
      _controller.add(mappedResults);
      
    } catch (error) {
      _controller.addError(error);
    }
  }

  /// Computes a hash code for a database row (Map<String, Object?>)
  int _computeRowHash(Map<String, Object?> row) {
    // Use a simple but effective hash combining algorithm
    var hash = 0;
    for (final entry in row.entries) {
      // Combine key and value hashes
      hash = _combineHash(hash, entry.key.hashCode);
      hash = _combineHash(hash, entry.value.hashCode);
    }
    return hash;
  }

  /// Combines two hash codes using a simple algorithm
  int _combineHash(int hash, int value) {
    hash = 0x1fffffff & (hash + value);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  /// Compares two hash sequences for equality
  bool _areHashSequencesEqual(List<int>? a, List<int>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    
    return true;
  }

  /// Removes cached entries that are no longer in the current result set
  void _cleanupCache(Set<int> currentHashes) {
    // Only keep cache entries that are still relevant
    _resultCache.removeWhere((hash, _) => !currentHashes.contains(hash));
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
    _lastResultHashes = null;
    _resultCache.clear();
  }

  /// Dispose of this streaming query
  void dispose() {
    _isActive = false;
    _resultCache.clear();
    _controller.close();
  }

  @override
  String toString() {
    return 'StreamingQuery(id: $_id, dependencies: $_dependencies, active: $_isActive, cached: ${_resultCache.length})';
  }
}