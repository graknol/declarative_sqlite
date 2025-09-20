import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class QueryListView<T> extends StatefulWidget {
  final DeclarativeDatabase? database;
  final void Function(QueryBuilder query) query;
  final T Function(Map<String, Object?>) mapper;
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
    required this.mapper,
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

class _QueryListViewState<T> extends State<QueryListView<T>> {
  AdvancedStreamingQuery<T>? _streamingQuery;
  StreamSubscription<List<T>>? _subscription;
  List<T>? _currentData;
  Object? _currentError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  @override
  void didUpdateWidget(QueryListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check if database changed
    if (widget.database != oldWidget.database) {
      _disposeStream();
      _initializeStream();
      return;
    }
    
    // If we have a streaming query, update it with new parameters
    if (_streamingQuery != null && widget.database != null) {
      // Build new query to check for changes
      final newBuilder = QueryBuilder();
      widget.query(newBuilder);
      
      // Update the streaming query (it will handle change detection internally)
      _streamingQuery!.updateQuery(
        newBuilder: newBuilder,
        newMapper: widget.mapper,
      );
    }
  }

  void _initializeStream() {
    if (widget.database == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // Create new query builder
    final builder = QueryBuilder();
    widget.query(builder);

    // Create advanced streaming query
    _streamingQuery = AdvancedStreamingQuery.create(
      id: 'query_list_view_${DateTime.now().millisecondsSinceEpoch}',
      builder: builder,
      database: widget.database!,
      mapper: widget.mapper,
    );

    // Subscribe to the stream
    _subscription = _streamingQuery!.stream.listen(
      (data) {
        if (mounted) {
          setState(() {
            _currentData = data;
            _currentError = null;
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _currentData = null;
            _currentError = error;
            _isLoading = false;
          });
        }
      },
    );
  }

  void _disposeStream() {
    _subscription?.cancel();
    _subscription = null;
    _streamingQuery?.dispose();
    _streamingQuery = null;
    _currentData = null;
    _currentError = null;
    _isLoading = true;
  }

  @override
  void dispose() {
    _disposeStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If no database is provided, show loading state
    if (widget.database == null) {
      return widget.loadingBuilder(context);
    }

    // Handle error state
    if (_currentError != null) {
      return widget.errorBuilder(context, _currentError!);
    }

    // Handle loading state
    if (_isLoading || _currentData == null) {
      return widget.loadingBuilder(context);
    }

    // Build the list with current data, passing through all ListView properties
    final items = _currentData!;
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
