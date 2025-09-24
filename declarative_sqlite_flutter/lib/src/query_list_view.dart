import 'package:declarative_sqlite/declarative_sqlite.dart';
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
      _createStreamingQuery(database);
    }
  }

  void _handleDatabaseChanges() {
    final newDatabase = _getDatabase(context);
    if (newDatabase != _currentDatabase) {
      _currentDatabase = newDatabase;
      if (newDatabase != null) {
        _createStreamingQuery(newDatabase);
      } else {
        _disposeStreamingQuery();
      }
    }
  }

  void _handleWidgetChanges(QueryListView<T> oldWidget) {
    // Check if query function changed (this is a simple reference check)
    // In a more sophisticated implementation, you could do deeper comparison
    final database = _currentDatabase;
    if (database != null && (widget.query != oldWidget.query || widget.mapper != oldWidget.mapper)) {
      _createStreamingQuery(database);
    }
  }

  void _disposeStreamingQuery() {
    if (_streamingQuery != null) {
      print('QueryListView: Disposing StreamingQuery id="${_streamingQuery!.id}"');
      // Fire and forget the async dispose - we don't want to block the UI
      _streamingQuery?.dispose().catchError((error) {
        print('QueryListView: Error during StreamingQuery dispose: $error');
      });
      _streamingQuery = null;
    }
  }



  void _createStreamingQuery(DeclarativeDatabase database) {
    // Dispose of existing query if any
    _disposeStreamingQuery();

    // Build the query
    final builder = QueryBuilder();
    widget.query(builder);

    // Create the effective mapper
    final T Function(Map<String, Object?>) effectiveMapper = _createEffectiveMapper(database);
    
    final queryId = 'query_list_view_${DateTime.now().millisecondsSinceEpoch}';
    print('QueryListView: Creating new StreamingQuery id="$queryId"');
    
    // Create new streaming query
    _streamingQuery = StreamingQuery.create(
      id: queryId,
      builder: builder,
      database: database,
      mapper: effectiveMapper,
    );
    
    print('QueryListView: StreamingQuery created id="$queryId" (will register when StreamBuilder listens)');
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
    _disposeStreamingQuery();
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
