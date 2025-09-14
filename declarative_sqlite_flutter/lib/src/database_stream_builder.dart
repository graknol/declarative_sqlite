import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'data_access_provider.dart';
import 'dart:async';

/// A widget that builds its child based on a reactive database stream with hot swapping support.
/// 
/// This widget automatically handles unsubscribe/subscribe behavior when the query changes,
/// ensuring proper resource management and supporting faceted search scenarios.
class DatabaseStreamBuilder<T> extends StatefulWidget {
  /// The data access instance for database operations
  /// If not provided, will be retrieved from DataAccessProvider
  final DataAccess? dataAccess;
  
  /// The query builder to execute (supports hot swapping)
  final QueryBuilder? query;
  
  /// Legacy stream support (deprecated, use query instead)
  final Stream<T>? stream;
  
  /// Function that creates a query result from DataAccess (legacy support)
  final Future<T> Function()? queryFunction;
  
  /// Builder function for the widget
  final Widget Function(BuildContext context, AsyncSnapshot<T> snapshot) builder;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display when stream has no data
  final Widget? noDataWidget;
  
  /// Widget builder for error states
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  
  /// Initial data for the stream
  final T? initialData;

  const DatabaseStreamBuilder({
    super.key,
    this.dataAccess,
    this.query,
    this.stream,
    this.queryFunction,
    required this.builder,
    this.loadingWidget,
    this.noDataWidget,
    this.errorBuilder,
    this.initialData,
  });

  @override
  State<DatabaseStreamBuilder<T>> createState() => _DatabaseStreamBuilderState<T>();
}

class _DatabaseStreamBuilderState<T> extends State<DatabaseStreamBuilder<T>> {
  StreamSubscription<T>? _subscription;
  AsyncSnapshot<T> _snapshot = const AsyncSnapshot.waiting();
  QueryBuilder? _currentQuery;
  DataAccess? _dataAccess;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialData != null 
      ? AsyncSnapshot.withData(ConnectionState.none, widget.initialData as T)
      : const AsyncSnapshot.waiting();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateDataAccess();
    _updateSubscription();
  }

  @override
  void didUpdateWidget(DatabaseStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check if query changed (value comparison)
    if (widget.query != oldWidget.query ||
        widget.stream != oldWidget.stream ||
        widget.queryFunction != oldWidget.queryFunction) {
      _updateSubscription();
    }
  }

  void _updateDataAccess() {
    final newDataAccess = getDataAccess(context, widget.dataAccess);
    if (_dataAccess != newDataAccess) {
      _dataAccess = newDataAccess;
      _updateSubscription();
    }
  }

  void _updateSubscription() {
    // Unsubscribe from old stream
    _subscription?.cancel();
    _subscription = null;
    
    Stream<T>? newStream;
    
    // Create new stream based on widget configuration
    if (widget.stream != null) {
      // Legacy stream mode
      newStream = widget.stream;
    } else if (widget.query != null && _dataAccess != null) {
      // New QueryBuilder-based mode with execution
      _currentQuery = widget.query;
      
      // Create a periodic stream that executes the QueryBuilder
      newStream = Stream.periodic(
        const Duration(milliseconds: 500),
        (_) async {
          try {
            final results = await widget.query!.executeMany(_dataAccess!);
            return results as T;
          } catch (e) {
            throw e;
          }
        },
      ).asyncMap((future) => future).distinct() as Stream<T>;
    } else if (widget.queryFunction != null) {
      // Legacy function mode - create a periodic stream
      newStream = Stream.periodic(
        const Duration(milliseconds: 500),
        (_) => widget.queryFunction!(),
      ).asyncMap((future) => future).distinct() as Stream<T>;
    }
    
    // Subscribe to new stream
    if (newStream != null) {
      setState(() {
        _snapshot = _snapshot.inState(ConnectionState.waiting);
      });
      
      _subscription = newStream.listen(
        (data) {
          if (mounted) {
            setState(() {
              _snapshot = AsyncSnapshot.withData(ConnectionState.active, data);
            });
          }
        },
        onError: (error, stackTrace) {
          if (mounted) {
            setState(() {
              _snapshot = AsyncSnapshot.withError(ConnectionState.active, error, stackTrace);
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _snapshot = _snapshot.inState(ConnectionState.done);
            });
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _snapshot);
  }
}

/// A convenience widget that provides default UI handling for database streams.
/// 
/// This widget wraps DatabaseStreamBuilder and provides default loading, error,
/// and empty state handling, making it easier to use in most scenarios.
class DatabaseWidgetBuilder<T> extends StatelessWidget {
  /// The data access instance for database operations
  /// If not provided, will be retrieved from DataAccessProvider
  final DataAccess? dataAccess;
  
  /// The query builder to execute (supports hot swapping)
  final QueryBuilder? query;
  
  /// Legacy stream support (deprecated, use query instead)
  final Stream<T>? stream;
  
  /// Function that creates a query result from DataAccess (legacy support)
  final Future<T> Function()? queryFunction;
  
  /// Builder function that receives just the data (no snapshot handling needed)
  final Widget Function(BuildContext context, T data) builder;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display when stream has no data
  final Widget? noDataWidget;
  
  /// Widget builder for error states
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  
  /// Initial data for the stream
  final T? initialData;

  const DatabaseWidgetBuilder({
    super.key,
    this.dataAccess,
    this.query,
    this.stream,
    this.queryFunction,
    required this.builder,
    this.loadingWidget,
    this.noDataWidget,
    this.errorBuilder,
    this.initialData,
  });

  @override
  Widget build(BuildContext context) {
    return DatabaseStreamBuilder<T>(
      dataAccess: dataAccess,
      query: query,
      stream: stream,
      queryFunction: queryFunction,
      initialData: initialData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (errorBuilder != null) {
            return errorBuilder!(context, snapshot.error!);
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ??
              const Center(
                child: CircularProgressIndicator(),
              );
        }

        final data = snapshot.data as T;
        
        // Handle empty collections
        if (data is List && (data as List).isEmpty) {
          return noDataWidget ??
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No data available',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
        }

        return builder(context, data);
      },
    );
  }
}
class DatabaseRecordBuilder extends StatelessWidget {
  /// The data access instance
  final DataAccess dataAccess;
  
  /// Table name to query
  final String tableName;
  
  /// Primary key value
  final dynamic primaryKey;
  
  /// Builder function that receives the record data
  final Widget Function(BuildContext context, Map<String, dynamic>? record) builder;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display when record is not found
  final Widget? notFoundWidget;
  
  /// Widget builder for error states
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const DatabaseRecordBuilder({
    super.key,
    required this.dataAccess,
    required this.tableName,
    required this.primaryKey,
    required this.builder,
    this.loadingWidget,
    this.notFoundWidget,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // Create a stream that watches for changes to this specific record
    final stream = dataAccess.streamRecord(tableName, primaryKey);

    return StreamBuilder<Map<String, dynamic>?>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (errorBuilder != null) {
            return errorBuilder!(context, snapshot.error!);
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ??
              const Center(
                child: CircularProgressIndicator(),
              );
        }

        final record = snapshot.data;
        
        if (record == null) {
          return notFoundWidget ??
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Record not found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
        }

        return builder(context, record);
      },
    );
  }
}

/// A widget that streams query results and rebuilds when they change.
class DatabaseQueryWidget extends StatelessWidget {
  /// The data access instance
  final DataAccess dataAccess;
  
  /// Table name to query
  final String tableName;
  
  /// Optional WHERE clause
  final String? where;
  
  /// Optional WHERE clause arguments
  final List<dynamic>? whereArgs;
  
  /// Optional ORDER BY clause
  final String? orderBy;
  
  /// Optional LIMIT
  final int? limit;
  
  /// Builder function that receives the query results
  final Widget Function(BuildContext context, List<Map<String, dynamic>> results) builder;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display when no results found
  final Widget? emptyWidget;
  
  /// Widget builder for error states
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const DatabaseQueryWidget({
    super.key,
    required this.dataAccess,
    required this.tableName,
    required this.builder,
    this.where,
    this.whereArgs,
    this.orderBy,
    this.limit,
    this.loadingWidget,
    this.emptyWidget,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final stream = dataAccess.streamQueryResults(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );

    return DatabaseStreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: builder,
      loadingWidget: loadingWidget,
      noDataWidget: emptyWidget,
      errorBuilder: errorBuilder,
    );
  }
}

/// A widget that executes a custom SQL query and streams the results.
class DatabaseSqlBuilder extends StatelessWidget {
  /// The data access instance
  final DataAccess dataAccess;
  
  /// SQL query to execute
  final String sql;
  
  /// Optional SQL arguments
  final List<dynamic>? arguments;
  
  /// Builder function that receives the query results
  final Widget Function(BuildContext context, List<Map<String, dynamic>> results) builder;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display when no results found
  final Widget? emptyWidget;
  
  /// Widget builder for error states
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const DatabaseSqlBuilder({
    super.key,
    required this.dataAccess,
    required this.sql,
    required this.builder,
    this.arguments,
    this.loadingWidget,
    this.emptyWidget,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final stream = dataAccess.streamSqlResults(sql, arguments);

    return DatabaseStreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: builder,
      loadingWidget: loadingWidget,
      noDataWidget: emptyWidget,
      errorBuilder: errorBuilder,
    );
  }
}

/// A widget that provides aggregate statistics from the database.
class DatabaseStatsBuilder extends StatelessWidget {
  /// The data access instance
  final DataAccess dataAccess;
  
  /// Table name to get stats from
  final String tableName;
  
  /// Optional WHERE clause for filtering
  final String? where;
  
  /// Optional WHERE clause arguments
  final List<dynamic>? whereArgs;
  
  /// Builder function that receives the statistics
  final Widget Function(BuildContext context, Map<String, dynamic> stats) builder;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget builder for error states
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const DatabaseStatsBuilder({
    super.key,
    required this.dataAccess,
    required this.tableName,
    required this.builder,
    this.where,
    this.whereArgs,
    this.loadingWidget,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getTableStats(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (errorBuilder != null) {
            return errorBuilder!(context, snapshot.error!);
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return loadingWidget ??
              const Center(
                child: CircularProgressIndicator(),
              );
        }

        return builder(context, snapshot.data!);
      },
    );
  }

  Future<Map<String, dynamic>> _getTableStats() async {
    // Get basic count
    final countSql = where != null
        ? 'SELECT COUNT(*) as count FROM $tableName WHERE $where'
        : 'SELECT COUNT(*) as count FROM $tableName';
    
    final countResult = await dataAccess.database.rawQuery(
      countSql,
      whereArgs,
    );
    
    final count = countResult.first['count'] as int;
    
    return {
      'count': count,
      'table': tableName,
      'filtered': where != null,
    };
  }
}