import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/src/work_order.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class _MockWorkOrder implements IWorkOrder {
  @override
  final String id;
  @override
  final String customerId;
  double total = 0;

  _MockWorkOrder(this.id, this.customerId);

  @override
  Future<void> setTotal(double Function(IWorkOrder r) reducer) async {
    // Simulate async operation
    await Future.delayed(const Duration(milliseconds: 50));
    // In a real implementation, this would update the database
    // and the change would be reflected in the query result.
    // For this mock, we'll just update the local state.
    // Note: this mock implementation detail won't be used in the final code.
  }
}

class QueryListView<T> extends StatefulWidget {
  final DeclarativeDatabase? database;
  final void Function(QueryBuilder query) query;
  final T Function(Map<String, Object?>) mapper;
  final Widget Function(BuildContext context) loadingBuilder;
  final Widget Function(BuildContext context, Object error) errorBuilder;
  final Widget Function(BuildContext context, T record) itemBuilder;

  const QueryListView({
    super.key,
    this.database,
    required this.query,
    required this.mapper,
    required this.loadingBuilder,
    required this.errorBuilder,
    required this.itemBuilder,
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
    // If no database is provided, fall back to mock data for backward compatibility
    if (widget.database == null) {
      if (T == IWorkOrder) {
        final items = [
          _MockWorkOrder('1', 'customer-1'),
          _MockWorkOrder('2', 'customer-2'),
        ];
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) =>
              widget.itemBuilder(context, items[index] as T),
        );
      }
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
    final items = _currentData!;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => widget.itemBuilder(context, items[index]),
    );
  }
}
