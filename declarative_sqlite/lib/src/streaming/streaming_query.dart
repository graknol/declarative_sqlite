import 'dart:async';
import 'dart:developer' as developer;

import 'package:rxdart/rxdart.dart';

import '../builders/query_builder.dart';
import '../builders/query_dependencies.dart';
import '../declarative_database.dart';
import 'query_dependency_analyzer.dart';
import 'query_emoji_utils.dart';

/// A cached result entry containing the mapped object and its system version
class _CachedResult<T> {
  final T object;
  final String systemVersion;
  
  const _CachedResult(this.object, this.systemVersion);
}

/// A streaming query that emits new results whenever the underlying data changes.
/// 
/// Uses sophisticated dependency analysis to track exactly which tables and columns
/// this query depends on, ensuring updates only occur when relevant data changes.
/// For complex queries, falls back to table-level dependencies for reliability.
/// 
/// Requires that all queried tables have system_id and system_version columns
/// for proper change detection and object caching optimization.
class StreamingQuery<T> {
  final String _id;
  late QueryBuilder _builder;
  late QueryDependencies _dependencies;
  final DeclarativeDatabase _database;
  late T Function(Map<String, Object?>) _mapper;
  
  late final BehaviorSubject<List<T>> _subject;
  bool _isActive = false;
  bool _isDisposed = false;
  
  /// Cache of previously mapped results indexed by their system_id
  final Map<String, _CachedResult<T>> _resultCache = {};
  
  /// System IDs of the last emitted result set for fast comparison
  List<String>? _lastResultSystemIds;
  
  /// Reference to the last mapper function for change detection
  T Function(Map<String, Object?>)? _lastMapper;
  
  /// Completer to track ongoing refresh operations
  Completer<void>? _ongoingRefresh;

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
        _mapper = mapper,
        _lastMapper = mapper {
    _subject = BehaviorSubject<List<T>>();
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

  /// The stream of query results with automatic replay of last value
  Stream<List<T>> get stream {
    return _subject.stream
        .doOnListen(_onListen)
        .doOnCancel(_onCancel);
  }

  /// Whether this query is currently active (has listeners)
  bool get isActive => _isActive;

  /// Updates the query builder and mapper with smart lifecycle management.
  /// 
  /// Re-analyzes dependencies when the query changes to ensure accurate
  /// dependency tracking. Invalidates cache when mapper changes.
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
      _dependencies = analyzer.analyzeQuery(newBuilder);
      
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
      _lastResultSystemIds = null;
    }

    // Execute new query if needed
    if (needsRefresh && _isActive) {
      await refresh();
    }
  }

  /// Returns true if this query might be affected by changes to the given table.
  /// 
  /// For complex queries, dependency analysis falls back to table-level tracking
  /// to ensure reliability when column-level analysis might miss edge cases.
  bool isAffectedByTable(String tableName) {
    return _dependencies.tables.contains(tableName) ||
           _dependencies.tables.any((table) => table.split(' ').first == tableName);
  }

  /// Returns true if this query might be affected by changes to the given column.
  /// 
  /// Uses precise column-level dependency tracking when possible. For wildcard
  /// queries or complex cases, falls back to table-level dependencies.
  bool isAffectedByColumn(String tableName, String columnName) {
    // If using wildcard selection, any column in referenced tables affects the query
    if (_dependencies.usesWildcard && 
        _dependencies.tables.any((table) => table.split(' ').first == tableName)) {
      return true;
    }
    
    // Check for specific column dependencies
    return _dependencies.columns.any((col) => 
        col.table == tableName && col.column == columnName);
  }

  /// Manually trigger a refresh of this query with system column optimization.
  /// 
  /// Requires that all queried tables have system_id and system_version columns
  /// for proper change detection and caching optimization.
  Future<void> refresh() async {
    // Check if disposed before starting
    if (_isDisposed || !_isActive) {
      return;
    }
    
    // Track this refresh operation
    _ongoingRefresh = Completer<void>();
    
    try {
      final rawResults = await _database.queryMapsWith(_builder);
      
      // Extract system IDs and versions for all raw results
      final newResultSystemIds = <String>[];
      final systemIdToVersion = <String, String>{};
      
      for (final rawRow in rawResults) {
        final systemId = rawRow['system_id'] as String;
        final systemVersion = rawRow['system_version'] as String;
        
        newResultSystemIds.add(systemId);
        systemIdToVersion[systemId] = systemVersion;
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
      
      // Update cached state and emit (only if not disposed)
      _lastResultSystemIds = newResultSystemIds;
      
      // Check if query was disposed during the async operation
      if (_isDisposed) {
        return;
      }
      
      // Only add to subject if it's not closed
      if (!_subject.isClosed) {
        _subject.add(mappedResults);
      }
      
    } catch (error, stackTrace) {
      final emoji = getAnimalEmoji(_id);
      developer.log('StreamingQuery.refresh: $emoji Error during refresh for id="$_id"', error: error, stackTrace: stackTrace, name: 'StreamingQuery');
      
      // Only add error if not disposed and subject is open
      if (!_isDisposed && !_subject.isClosed) {
        _subject.addError(error);
      }
    } finally {
      // Mark refresh as completed
      _ongoingRefresh?.complete();
      _ongoingRefresh = null;
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
  void _onListen() {
    _isActive = true;
    _database.streamManager.register(this);
    
    // Trigger initial refresh asynchronously
    refresh().catchError((error, stackTrace) {
      if (!_isDisposed && !_subject.isClosed) {
        _subject.addError(error);
      }
    });
  }

  /// Called when the last listener unsubscribes  
  void _onCancel() {
    _isActive = false;
    _lastResultSystemIds = null;
    _database.streamManager.unregisterOnly(_id);
    _resultCache.clear();
  }

  /// Dispose of this streaming query
  Future<void> dispose() async {
    final emoji = getAnimalEmoji(_id);
    developer.log('StreamingQuery.dispose: $emoji Disposing query id="$_id"', name: 'StreamingQuery');
    
    if (_isDisposed) {
      developer.log('StreamingQuery.dispose: $emoji Already disposed, skipping for id="$_id"', name: 'StreamingQuery');
      return;
    }
    
    _isDisposed = true;
    _isActive = false;
    
    // Wait for any ongoing refresh to complete
    if (_ongoingRefresh != null && !_ongoingRefresh!.isCompleted) {
      developer.log('StreamingQuery.dispose: $emoji Waiting for ongoing refresh to complete for id="$_id"', name: 'StreamingQuery');
      try {
        await _ongoingRefresh!.future.timeout(Duration(seconds: 5));
      } catch (e) {
        developer.log('StreamingQuery.dispose: $emoji Timeout waiting for refresh completion for id="$_id"', name: 'StreamingQuery');
      }
    }
    
    _resultCache.clear();
    
    if (!_subject.isClosed) {
      await _subject.close();
    }
    
    developer.log('StreamingQuery.dispose: $emoji Successfully disposed query id="$_id"', name: 'StreamingQuery');
  }

  @override
  String toString() {
    return 'StreamingQuery(id: $_id, dependencies: $_dependencies, active: $_isActive, cached: ${_resultCache.length})';
  }
}