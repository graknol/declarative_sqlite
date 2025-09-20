import 'dart:async';
import '../builders/query_builder.dart';
import '../database.dart';
import 'streaming_query.dart';
import 'query_dependency_analyzer.dart';

/// Advanced streaming query manager that handles smart lifecycle management
/// with query equality checking and cache invalidation
class AdvancedStreamingQuery<T> {
  final String _id;
  late QueryBuilder _builder;
  late QueryDependencies _dependencies;
  final DeclarativeDatabase _database;
  late T Function(Map<String, Object?>) _mapper;
  
  late final StreamController<List<T>> _controller;
  bool _isActive = false;
  List<T>? _lastResults;
  
  /// Cache of previously mapped results indexed by their hash codes
  final Map<int, _CachedResult<T>> _resultCache = {};
  
  /// Hash codes of the last emitted result set for fast comparison
  List<int>? _lastResultHashes;
  
  /// Reference to the last mapper function for change detection
  T Function(Map<String, Object?>)? _lastMapper;

  AdvancedStreamingQuery._({
    required String id,
    required QueryBuilder builder,
    required DeclarativeDatabase database,
    required T Function(Map<String, Object?>) mapper,
  })  : _id = id,
        _database = database {
    _builder = builder;
    _mapper = mapper;
    _lastMapper = mapper;
    
    // Analyze dependencies
    final analyzer = QueryDependencyAnalyzer(database.schema);
    _dependencies = analyzer.analyze(builder);
    
    _controller = StreamController<List<T>>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  /// Factory constructor to create an advanced streaming query
  factory AdvancedStreamingQuery.create({
    required String id,
    required QueryBuilder builder,
    required DeclarativeDatabase database,
    required T Function(Map<String, Object?>) mapper,
  }) {
    return AdvancedStreamingQuery._(
      id: id,
      builder: builder,
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

  /// Updates the query builder and mapper with smart lifecycle management
  Future<void> updateQuery({
    QueryBuilder? newBuilder,
    T Function(Map<String, Object?>)? newMapper,
  }) async {
    bool needsRefresh = false;
    bool needsCacheInvalidation = false;

    // Check if query builder changed (using Equatable value equality)
    if (newBuilder != null && newBuilder != _builder) {
      _builder = newBuilder;
      
      // Re-analyze dependencies for the new query
      final analyzer = QueryDependencyAnalyzer(_database.schema);
      _dependencies = analyzer.analyze(newBuilder);
      
      needsRefresh = true;
    }

    // Check if mapper function changed (using reference equality)
    if (newMapper != null && !identical(newMapper, _lastMapper)) {
      _mapper = newMapper;
      _lastMapper = newMapper;
      needsCacheInvalidation = true;
      needsRefresh = true;
    }

    // Invalidate cache if mapper changed
    if (needsCacheInvalidation) {
      _resultCache.clear();
      _lastResultHashes = null;
    }

    // Execute new query if needed
    if (needsRefresh && _isActive) {
      await refresh();
    }
  }

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

  /// Computes a hash code for a database row using system columns for efficiency
  int _computeRowHash(Map<String, Object?> row) {
    // Optimization: Use system columns (system_id + system_version) instead of full object hashing
    // system_version is updated with HLC timestamp on every insert/update, making this sufficient
    // for change detection while being much faster than full object hashing
    
    final systemId = row['system_id'];
    final systemVersion = row['system_version'];
    
    // If system columns are available, use them for fast change detection
    if (systemId != null && systemVersion != null) {
      return _combineHash(systemId.hashCode, systemVersion.hashCode);
    }
    
    // Fallback to full object hashing if system columns are not available
    // This maintains compatibility with tables that don't have system columns
    var hash = 0;
    for (final entry in row.entries) {
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
    // Only keep cache entries that are still relevant to prevent infinite growth
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
    return 'AdvancedStreamingQuery(id: $_id, dependencies: $_dependencies, active: $_isActive, cached: ${_resultCache.length})';
  }
}

/// A cached result entry containing the mapped object and its hash
class _CachedResult<T> {
  final T object;
  final int hashCode;
  
  const _CachedResult(this.object, this.hashCode);
}