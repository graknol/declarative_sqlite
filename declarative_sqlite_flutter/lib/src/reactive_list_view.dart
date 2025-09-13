import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// A ListView widget that automatically updates when the underlying database table changes.
/// 
/// This widget uses the reactive streaming capabilities of declarative_sqlite to
/// automatically rebuild when data in the specified table is modified.
class ReactiveListView extends StatefulWidget {
  /// The data access instance for database operations
  final DataAccess dataAccess;
  
  /// Name of the table to watch for changes
  final String tableName;
  
  /// Builder function for individual list items
  final Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder;
  
  /// Optional WHERE clause to filter results
  final String? where;
  
  /// Optional WHERE clause arguments
  final List<dynamic>? whereArgs;
  
  /// Optional ORDER BY clause
  final String? orderBy;
  
  /// Widget to display when the list is empty
  final Widget? emptyWidget;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display when an error occurs
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  
  /// Scroll controller for the ListView
  final ScrollController? controller;
  
  /// Whether the list should be physics-enabled
  final ScrollPhysics? physics;
  
  /// Whether the list should shrink-wrap
  final bool shrinkWrap;
  
  /// Padding for the ListView
  final EdgeInsetsGeometry? padding;

  const ReactiveListView({
    super.key,
    required this.dataAccess,
    required this.tableName,
    required this.itemBuilder,
    this.where,
    this.whereArgs,
    this.orderBy,
    this.emptyWidget,
    this.loadingWidget,
    this.errorBuilder,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
  });

  /// Creates a ReactiveListView with a builder pattern similar to ListView.builder
  factory ReactiveListView.builder({
    Key? key,
    required DataAccess dataAccess,
    required String tableName,
    required Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    Widget? emptyWidget,
    Widget? loadingWidget,
    Widget Function(BuildContext context, Object error)? errorBuilder,
    ScrollController? controller,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    EdgeInsetsGeometry? padding,
  }) {
    return ReactiveListView(
      key: key,
      dataAccess: dataAccess,
      tableName: tableName,
      itemBuilder: itemBuilder,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      emptyWidget: emptyWidget,
      loadingWidget: loadingWidget,
      errorBuilder: errorBuilder,
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      padding: padding,
    );
  }

  @override
  State<ReactiveListView> createState() => _ReactiveListViewState();
}

class _ReactiveListViewState extends State<ReactiveListView> {
  late Stream<List<Map<String, dynamic>>> _dataStream;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  @override
  void didUpdateWidget(ReactiveListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Reinitialize stream if key parameters changed
    if (oldWidget.tableName != widget.tableName ||
        oldWidget.where != widget.where ||
        oldWidget.whereArgs != widget.whereArgs ||
        oldWidget.orderBy != widget.orderBy ||
        oldWidget.dataAccess != widget.dataAccess) {
      _initializeStream();
    }
  }

  void _initializeStream() {
    // Create a reactive stream that watches for changes to this table
    _dataStream = widget.dataAccess.streamQueryResults(
      widget.tableName,
      where: widget.where,
      whereArgs: widget.whereArgs,
      orderBy: widget.orderBy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _dataStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, snapshot.error!);
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(height: 8),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return widget.loadingWidget ?? 
            const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data!;
        
        if (items.isEmpty) {
          return widget.emptyWidget ?? 
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No items found', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
        }

        return ListView.builder(
          controller: widget.controller,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          padding: widget.padding,
          itemCount: items.length,
          itemBuilder: (context, index) {
            return widget.itemBuilder(context, items[index]);
          },
        );
      },
    );
  }
}

/// A SliverList widget that automatically updates when the underlying database table changes.
class ReactiveSliverList extends StatefulWidget {
  /// The data access instance for database operations
  final DataAccess dataAccess;
  
  /// Name of the table to watch for changes
  final String tableName;
  
  /// Builder function for individual list items
  final Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder;
  
  /// Optional WHERE clause to filter results
  final String? where;
  
  /// Optional WHERE clause arguments
  final List<dynamic>? whereArgs;
  
  /// Optional ORDER BY clause
  final String? orderBy;

  const ReactiveSliverList({
    super.key,
    required this.dataAccess,
    required this.tableName,
    required this.itemBuilder,
    this.where,
    this.whereArgs,
    this.orderBy,
  });

  @override
  State<ReactiveSliverList> createState() => _ReactiveSliverListState();
}

class _ReactiveSliverListState extends State<ReactiveSliverList> {
  late Stream<List<Map<String, dynamic>>> _dataStream;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  @override
  void didUpdateWidget(ReactiveSliverList oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.tableName != widget.tableName ||
        oldWidget.where != widget.where ||
        oldWidget.whereArgs != widget.whereArgs ||
        oldWidget.orderBy != widget.orderBy ||
        oldWidget.dataAccess != widget.dataAccess) {
      _initializeStream();
    }
  }

  void _initializeStream() {
    _dataStream = widget.dataAccess.streamQueryResults(
      widget.tableName,
      where: widget.where,
      whereArgs: widget.whereArgs,
      orderBy: widget.orderBy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _dataStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final items = snapshot.data!;
        
        return SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            return widget.itemBuilder(context, items[index]);
          },
        );
      },
    );
  }
}