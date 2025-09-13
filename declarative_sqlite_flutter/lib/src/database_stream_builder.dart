import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// A widget that builds its child based on a reactive database stream.
/// 
/// Similar to StreamBuilder but specifically designed for database queries
/// with built-in error handling and loading states.
class DatabaseStreamBuilder<T> extends StatelessWidget {
  /// The stream to listen to
  final Stream<T> stream;
  
  /// Builder function for the widget
  final Widget Function(BuildContext context, T data) builder;
  
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
    required this.stream,
    required this.builder,
    this.loadingWidget,
    this.noDataWidget,
    this.errorBuilder,
    this.initialData,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
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

        if (!snapshot.hasData) {
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

/// A widget that streams a single record from the database and rebuilds when it changes.
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
class DatabaseQueryBuilder extends StatelessWidget {
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

  const DatabaseQueryBuilder({
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