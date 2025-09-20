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
    if (_hasDatabaseChanged(oldWidget)) {
      _handleDatabaseChange();
      return;
    }
    
    // Update query if we have an active streaming query
    _updateQueryIfNeeded();
  }

  bool _hasDatabaseChanged(QueryListView<T> oldWidget) {
    return widget.database != oldWidget.database;
  }

  void _handleDatabaseChange() {
    _disposeStream();
    _initializeStream();
  }

  void _updateQueryIfNeeded() {
    if (_streamingQuery != null && widget.database != null) {
      final newBuilder = _buildNewQuery();
      _updateStreamingQuery(newBuilder);
    }
  }

  QueryBuilder _buildNewQuery() {
    final newBuilder = QueryBuilder();
    widget.query(newBuilder);
    return newBuilder;
  }

  void _updateStreamingQuery(QueryBuilder newBuilder) {
    _streamingQuery!.updateQuery(
      newBuilder: newBuilder,
      newMapper: widget.mapper,
    );
  }

  void _initializeStream() {
    if (!_canInitializeStream()) {
      _setLoadingComplete();
      return;
    }

    final builder = _buildQuery();
    _createStreamingQuery(builder);
    _subscribeToStream();
  }

  bool _canInitializeStream() {
    return widget.database != null;
  }

  void _setLoadingComplete() {
    setState(() {
      _isLoading = false;
    });
  }

  QueryBuilder _buildQuery() {
    final builder = QueryBuilder();
    widget.query(builder);
    return builder;
  }

  void _createStreamingQuery(QueryBuilder builder) {
    _streamingQuery = AdvancedStreamingQuery.create(
      id: 'query_list_view_${DateTime.now().millisecondsSinceEpoch}',
      builder: builder,
      database: widget.database!,
      mapper: widget.mapper,
    );
  }

  void _subscribeToStream() {
    _subscription = _streamingQuery!.stream.listen(
      _handleStreamData,
      onError: _handleStreamError,
    );
  }

  void _handleStreamData(List<T> data) {
    if (mounted) {
      setState(() {
        _currentData = data;
        _currentError = null;
        _isLoading = false;
      });
    }
  }

  void _handleStreamError(Object error) {
    if (mounted) {
      setState(() {
        _currentData = null;
        _currentError = error;
        _isLoading = false;
      });
    }
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
    return _buildStateBasedWidget(context);
  }

  Widget _buildStateBasedWidget(BuildContext context) {
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

    // Build the list with current data
    return _buildListView();
  }

  Widget _buildListView() {
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
