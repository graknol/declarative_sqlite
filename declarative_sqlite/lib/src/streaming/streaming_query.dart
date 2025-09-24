import 'dart:async';

import '../builders/query_builder.dart';
import '../builders/query_dependencies.dart';
import '../database.dart';
import 'query_dependency_analyzer.dart';

/// A cached result entry containing the mapped object and its system version
class _CachedResult<T> {
  final T object;
  final String systemVersion;
  
  const _CachedResult(this.object, this.systemVersion);
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
  
  /// Cache of previously mapped results indexed by their system_id
  final Map<String, _CachedResult<T>> _resultCache = {};
  
  /// System IDs of the last emitted result set for fast comparison
  List<String>? _lastResultSystemIds;

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
    final dependencies = analyzer.analyzeQuery(builder);
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
    return _dependencies.tables.contains(tableName) ||
           _dependencies.tables.any((table) => table.split(' ').first == tableName);
  }

  /// Returns true if this query might be affected by changes to the given column
  bool isAffectedByColumn(String tableName, String columnName) {
    return _dependencies.usesWildcard && _dependencies.tables.any((table) => table.split(' ').first == tableName) ||
           _dependencies.columns.any((col) => col.table == tableName && col.column == columnName);
  }

  /// Manually trigger a refresh of this query with hash-based optimization
  Future<void> refresh() async {
    if (!_isActive) return;
    
    try {
      final rawResults = await _database.queryMapsWith(_builder);
      
      // Extract system IDs and versions for all raw results
      final newResultSystemIds = <String>[];
      final systemIdToVersion = <String, String>{};
      
      for (final rawRow in rawResults) {
        final systemId = rawRow['system_id'] as String?;
        final systemVersion = rawRow['system_version'] as String?;
        
        if (systemId != null && systemVersion != null) {
          newResultSystemIds.add(systemId);
          systemIdToVersion[systemId] = systemVersion;
        } else {
          // Fallback for rows without system columns: generate unique identifier
          final fallbackId = 'fallback_${newResultSystemIds.length}';
          newResultSystemIds.add(fallbackId);
          systemIdToVersion[fallbackId] = DateTime.now().millisecondsSinceEpoch.toString();
        }
      }
      
      // Quick check: if system ID sequence is identical, check for version changes
      bool hasChanges = !_areSystemIdSequencesEqual(newResultSystemIds, _lastResultSystemIds);
      if (!hasChanges && _lastResultSystemIds != null) {
        // Check if any system versions have changed
        for (final systemId in newResultSystemIds) {
          final cached = _resultCache[systemId];
          final currentVersion = systemIdToVersion[systemId];
          if (cached == null || cached.systemVersion != currentVersion) {
            hasChanges = true;
            break;
          }
        }
      }
      
      if (!hasChanges) {
        return; // No changes, no emission needed
      }
      
      // Build the new result list using cache optimization
      final mappedResults = <T>[];
      
      for (int i = 0; i < rawResults.length; i++) {
        final rawRow = rawResults[i];
        final systemId = newResultSystemIds[i];
        final systemVersion = systemIdToVersion[systemId]!;
        
        // Check if we have this row cached with same version
        final cached = _resultCache[systemId];
        if (cached != null && cached.systemVersion == systemVersion) {
          // Use cached mapped object (reference equality maintained)
          mappedResults.add(cached.object);
        } else {
          // Map new row and cache it
          final mappedRow = _mapper(rawRow);
          final cachedResult = _CachedResult(mappedRow, systemVersion);
          _resultCache[systemId] = cachedResult;
          mappedResults.add(mappedRow);
        }
      }
      
      // Clean up cache: remove entries not in current result set
      _cleanupCache(newResultSystemIds.toSet());
      
      // Update cached state and emit
      _lastResultSystemIds = newResultSystemIds;
      _controller.add(mappedResults);
      
    } catch (error) {
      _controller.addError(error);
    }
  }

  /// Compares two system ID sequences for equality
  bool _areSystemIdSequencesEqual(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    
    return true;
  }

  /// Removes cached entries that are no longer in the current result set
  void _cleanupCache(Set<String> currentSystemIds) {
    // Only keep cache entries that are still relevant to prevent infinite growth
    _resultCache.removeWhere((systemId, _) => !currentSystemIds.contains(systemId));
  }

  /// Called when the first listener subscribes
  Future<void> _onListen() async {
    _isActive = true;
    await refresh();
  }

  /// Called when the last listener unsubscribes  
  void _onCancel() {
    _isActive = false;
    _lastResultSystemIds = null;
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