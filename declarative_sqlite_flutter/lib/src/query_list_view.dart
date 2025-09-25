import 'dart:developer' as developer;

import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/streaming/query_emoji_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'database_provider.dart';

class QueryListView<T extends DbRecord> extends StatefulWidget {
  final DeclarativeDatabase? database;
  final void Function(QueryBuilder query) query;
  final T Function(Map<String, Object?>, DeclarativeDatabase)? mapper;
  final Widget Function(BuildContext context) loadingBuilder;
  final Widget Function(BuildContext context, Object error) errorBuilder;
  final Widget Function(BuildContext context, T record) itemBuilder;
  
  // ListView properties for Flutter SDK compatibility
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final double? itemExtent;
  final Widget? prototypeItem;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;
  final double? cacheExtent;
  final int? semanticChildCount;
  final DragStartBehavior dragStartBehavior;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final String? restorationId;
  final Clip clipBehavior;

  const QueryListView({
    super.key,
    this.database,
    required this.query,
    this.mapper,
    required this.loadingBuilder,
    required this.errorBuilder,
    required this.itemBuilder,
    // ListView properties with Flutter SDK defaults
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    this.prototypeItem,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.cacheExtent,
    this.semanticChildCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
  });

  @override
  State<QueryListView<T>> createState() => _QueryListViewState<T>();
}

class _QueryListViewState<T extends DbRecord> extends State<QueryListView<T>> {
  StreamingQuery<T>? _streamingQuery;
  DeclarativeDatabase? _currentDatabase;
  String? _lastQuerySignature; // Track query changes more efficiently

  @override
  void initState() {
    super.initState();
    // Initialize streaming query in initState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeStreamingQuery();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if database changed due to InheritedWidget changes
    _handleDatabaseChanges();
  }

  @override
  void didUpdateWidget(QueryListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handle widget property changes
    _handleWidgetChanges(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    // Get database from widget parameter or DatabaseProvider
    final database = _getDatabase(context);
    
    // If no database is available, show loading state
    if (database == null) {
      return widget.loadingBuilder(context);
    }

    // If no streaming query is ready, show loading state
    if (_streamingQuery == null) {
      return widget.loadingBuilder(context);
    }
    
    // Use StreamBuilder to handle all stream lifecycle management
    return StreamBuilder<List<T>>(
      stream: _streamingQuery!.stream,
      builder: (context, snapshot) {
        // Handle error state
        if (snapshot.hasError) {
          return widget.errorBuilder(context, snapshot.error!);
        }

        // Handle loading state (waiting for first data or no data yet)
        if (!snapshot.hasData) {
          return widget.loadingBuilder(context);
        }

        // Build the list with current data
        return _buildListView(snapshot.data!);
      },
    );
  }

  /// Gets the database from widget parameter or DatabaseProvider context
  DeclarativeDatabase? _getDatabase(BuildContext context) {
    // First try the explicitly provided database
    if (widget.database != null) {
      return widget.database;
    }
    
    // Fall back to DatabaseProvider context
    return DatabaseProvider.maybeOf(context);
  }

  void _initializeStreamingQuery() {
    final database = _getDatabase(context);
    if (database != null) {
      _currentDatabase = database;
      _createStreamingQuery(database).then((_) {
        // Trigger rebuild now that streaming query is ready
        if (mounted) setState(() {});
      });
    }
  }

  void _handleDatabaseChanges() {
    final newDatabase = _getDatabase(context);
    if (newDatabase != _currentDatabase) {
      _currentDatabase = newDatabase;
      if (newDatabase != null) {
        _createStreamingQuery(newDatabase).then((_) {
          // Trigger rebuild now that streaming query is ready
          if (mounted) setState(() {});
        });
      } else {
        _disposeStreamingQuery().then((_) {
          // Trigger rebuild to show loading state
          if (mounted) setState(() {});
        });
      }
    }
  }

  void _handleWidgetChanges(QueryListView<T> oldWidget) {
    final database = _currentDatabase;
    if (database == null) return;
    
    // Generate signature for current query to detect meaningful changes
    final currentSignature = _generateQuerySignature();
    
    // Only recreate the streaming query if there's a meaningful change
    if (_lastQuerySignature != currentSignature || widget.mapper != oldWidget.mapper) {
      developer.log('QueryListView: Query changed, recreating stream', name: 'QueryListView');
      _createStreamingQuery(database).then((_) {
        _lastQuerySignature = currentSignature;
        // Trigger rebuild now that streaming query has been recreated
        if (mounted) setState(() {});
      });
    }
  }
  
  /// Generate a signature for the current query to detect meaningful changes
  String _generateQuerySignature() {
    final builder = QueryBuilder();
    widget.query(builder);
    
    // Build the SQL to use as signature (this captures all meaningful changes)
    try {
      final (sql, params) = builder.build();
      return '$sql|${params.join(',')}';
    } catch (e) {
      // If build fails, fall back to table name + hash of widget.query function
      return '${builder.tableName}_${widget.query.hashCode}';
    }
  }

  Future<void> _disposeStreamingQuery() async {
    if (_streamingQuery != null) {
      final emoji = getAnimalEmoji(_streamingQuery!.id);
      try {
        // Wait for disposal to complete to avoid race conditions
        await _streamingQuery!.dispose();
        developer.log('QueryListView: $emoji Successfully disposed streaming query', name: 'QueryListView');
      } catch (error) {
        developer.log('QueryListView: $emoji Error during dispose: $error', name: 'QueryListView');
      }
      _streamingQuery = null;
    }
  }

  Future<void> _createStreamingQuery(DeclarativeDatabase database) async {
    // Dispose of existing query if any and wait for completion
    await _disposeStreamingQuery();

    // Build the query
    final builder = QueryBuilder();
    widget.query(builder);

    // Create the effective mapper
    final T Function(Map<String, Object?>) effectiveMapper = _createEffectiveMapper(database);
    
    final queryId = 'query_list_view_${DateTime.now().millisecondsSinceEpoch}';
    final emoji = getAnimalEmoji(queryId);
    developer.log('QueryListView: $emoji Creating new streaming query with id="$queryId"', name: 'QueryListView');
    
    // Create new streaming query with RxDart-enhanced lifecycle management
    _streamingQuery = StreamingQuery.create(
      id: queryId,
      builder: builder,
      database: database,
      mapper: effectiveMapper,
    );
  }

  T Function(Map<String, Object?>) _createEffectiveMapper(DeclarativeDatabase database) {
    if (widget.mapper != null) {
      return (data) => widget.mapper!(data, database);
    } else {
      // Try to get mapper from registry
      if (!RecordMapFactoryRegistry.hasFactory<T>()) {
        throw ArgumentError(
          'No mapper provided and no factory registered for type $T. '
          'Either provide a mapper parameter or register a factory using '
          'RecordMapFactoryRegistry.register<$T>(factory).'
        );
      }
      return (data) => RecordMapFactoryRegistry.create<T>(data, database);
    }
  }

  @override
  void dispose() {
    // StreamBuilder handles stream subscription lifecycle automatically
    // We only need to dispose of our StreamingQuery
    // Note: We don't await this since dispose() must be synchronous
    _disposeStreamingQuery().catchError((error) {
      developer.log('QueryListView: Error during widget dispose: $error', name: 'QueryListView');
    });
    super.dispose();
  }

  Widget _buildListView(List<T> items) {
    return ListView.builder(
      // Core ListView.builder properties
      itemCount: items.length,
      itemBuilder: (context, index) => widget.itemBuilder(context, items[index]),
      
      // Pass through all ListView properties to maintain Flutter SDK compatibility
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      controller: widget.controller,
      primary: widget.primary,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      itemExtent: widget.itemExtent,
      prototypeItem: widget.prototypeItem,
      addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
      addRepaintBoundaries: widget.addRepaintBoundaries,
      addSemanticIndexes: widget.addSemanticIndexes,
      cacheExtent: widget.cacheExtent,
      semanticChildCount: widget.semanticChildCount,
      dragStartBehavior: widget.dragStartBehavior,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      restorationId: widget.restorationId,
      clipBehavior: widget.clipBehavior,
    );
  }
}
