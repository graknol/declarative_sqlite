import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'database_stream_builder.dart';

/// A data wrapper that provides CRUD operations for a specific database record.
/// 
/// This class encapsulates both the current data of a record and the operations
/// that can be performed on it, making it easy to build two-way data bindings.
class RecordData {
  /// The current data of the record
  final Map<String, dynamic> data;
  
  /// The data access instance for performing operations
  final DataAccess dataAccess;
  
  /// The table name this record belongs to
  final String tableName;
  
  /// The primary key value of this record
  final dynamic primaryKey;
  
  /// The name of the primary key column
  final String primaryKeyColumn;

  const RecordData({
    required this.data,
    required this.dataAccess,
    required this.tableName,
    required this.primaryKey,
    required this.primaryKeyColumn,
  });

  /// Update a single column value
  Future<void> updateColumn(String columnName, dynamic value) async {
    await dataAccess.updateColumn(
      tableName,
      primaryKey,
      columnName,
      value,
    );
  }

  /// Update multiple columns at once
  Future<void> updateColumns(Map<String, dynamic> updates) async {
    await dataAccess.update(
      tableName,
      updates,
      where: '$primaryKeyColumn = ?',
      whereArgs: [primaryKey],
    );
  }

  /// Delete this record
  Future<void> delete() async {
    await dataAccess.delete(
      tableName,
      where: '$primaryKeyColumn = ?',
      whereArgs: [primaryKey],
    );
  }

  /// Get the value of a specific column
  T? getValue<T>(String columnName) {
    return data[columnName] as T?;
  }

  /// Check if a column has a value (not null)
  bool hasValue(String columnName) {
    return data.containsKey(columnName) && data[columnName] != null;
  }

  /// Get all column names in this record
  Set<String> get columnNames => data.keys.toSet();

  /// Create a copy of this record data with updated values
  RecordData copyWith({
    Map<String, dynamic>? data,
    DataAccess? dataAccess,
    String? tableName,
    dynamic primaryKey,
    String? primaryKeyColumn,
  }) {
    return RecordData(
      data: data ?? this.data,
      dataAccess: dataAccess ?? this.dataAccess,
      tableName: tableName ?? this.tableName,
      primaryKey: primaryKey ?? this.primaryKey,
      primaryKeyColumn: primaryKeyColumn ?? this.primaryKeyColumn,
    );
  }
}

/// A low-level building block widget that provides reactive access to a single database record.
/// 
/// This widget automatically rebuilds when the specified record changes and provides
/// both the current data and CRUD operations through a [RecordData] wrapper.
/// This makes it easy to build two-way data bindings and custom reactive widgets.
/// 
/// ## Example Usage
/// 
/// ```dart
/// ReactiveRecordBuilder(
///   dataAccess: dataAccess,
///   tableName: 'users',
///   primaryKey: userId,
///   builder: (context, recordData) {
///     if (recordData == null) {
///       return Text('Record not found');
///     }
///     
///     return Column(
///       children: [
///         Text('Name: ${recordData.getValue<String>('name')}'),
///         ElevatedButton(
///           onPressed: () => recordData.updateColumn('name', 'New Name'),
///           child: Text('Update Name'),
///         ),
///         ElevatedButton(
///           onPressed: () => recordData.delete(),
///           child: Text('Delete Record'),
///         ),
///       ],
///     );
///   },
/// )
/// ```
class ReactiveRecordBuilder extends StatelessWidget {
  /// The data access instance for database operations
  final DataAccess dataAccess;
  
  /// Name of the table containing the record
  final String tableName;
  
  /// Primary key value of the record to watch
  final dynamic primaryKey;
  
  /// Name of the primary key column (defaults to 'id')
  final String primaryKeyColumn;
  
  /// Builder function that receives the current record data and CRUD operations
  final Widget Function(BuildContext context, RecordData? recordData) builder;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display on error
  final Widget Function(Object error)? errorBuilder;

  const ReactiveRecordBuilder({
    super.key,
    required this.dataAccess,
    required this.tableName,
    required this.primaryKey,
    required this.builder,
    this.primaryKeyColumn = 'id',
    this.loadingWidget,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return DatabaseStreamBuilder<Map<String, dynamic>?>(
      dataAccess: dataAccess,
      query: () => dataAccess.getByPrimaryKey(tableName, primaryKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ?? const CircularProgressIndicator();
        }

        if (snapshot.hasError) {
          if (errorBuilder != null) {
            return errorBuilder!(snapshot.error!);
          }
          return Text('Error: ${snapshot.error}');
        }

        final data = snapshot.data;
        if (data == null) {
          return builder(context, null);
        }

        final recordData = RecordData(
          data: data,
          dataAccess: dataAccess,
          tableName: tableName,
          primaryKey: primaryKey,
          primaryKeyColumn: primaryKeyColumn,
        );

        return builder(context, recordData);
      },
    );
  }
}

/// A variant of [ReactiveRecordBuilder] that works with query conditions instead of primary key.
/// 
/// This widget is useful when you want to watch a record that might not have a known primary key,
/// or when you want to watch the first record matching certain conditions.
class ReactiveRecordBuilderWhere extends StatelessWidget {
  /// The data access instance for database operations
  final DataAccess dataAccess;
  
  /// Name of the table to query
  final String tableName;
  
  /// WHERE clause for finding the record
  final String? where;
  
  /// Arguments for the WHERE clause
  final List<dynamic>? whereArgs;
  
  /// ORDER BY clause (useful when multiple records might match)
  final String? orderBy;
  
  /// Name of the primary key column (defaults to 'id')
  final String primaryKeyColumn;
  
  /// Builder function that receives the current record data and CRUD operations
  final Widget Function(BuildContext context, RecordData? recordData) builder;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display on error
  final Widget Function(Object error)? errorBuilder;

  const ReactiveRecordBuilderWhere({
    super.key,
    required this.dataAccess,
    required this.tableName,
    required this.builder,
    this.where,
    this.whereArgs,
    this.orderBy,
    this.primaryKeyColumn = 'id',
    this.loadingWidget,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return DatabaseStreamBuilder<Map<String, dynamic>?>(
      dataAccess: dataAccess,
      query: () async {
        final results = await dataAccess.getAllWhere(
          tableName,
          where: where,
          whereArgs: whereArgs,
          orderBy: orderBy,
          limit: 1,
        );
        return results.isNotEmpty ? results.first : null;
      },
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ?? const CircularProgressIndicator();
        }

        if (snapshot.hasError) {
          if (errorBuilder != null) {
            return errorBuilder!(snapshot.error!);
          }
          return Text('Error: ${snapshot.error}');
        }

        final data = snapshot.data;
        if (data == null) {
          return builder(context, null);
        }

        final primaryKey = data[primaryKeyColumn];
        final recordData = RecordData(
          data: data,
          dataAccess: dataAccess,
          tableName: tableName,
          primaryKey: primaryKey,
          primaryKeyColumn: primaryKeyColumn,
        );

        return builder(context, recordData);
      },
    );
  }
}

/// A convenience widget for creating reactive forms using [ReactiveRecordBuilder].
/// 
/// This widget provides a form-like interface where child widgets can access
/// the current record data and make updates through the provided [RecordData].
class ReactiveRecordForm extends StatelessWidget {
  /// The data access instance for database operations
  final DataAccess dataAccess;
  
  /// Name of the table containing the record
  final String tableName;
  
  /// Primary key value of the record to edit
  final dynamic primaryKey;
  
  /// Name of the primary key column (defaults to 'id')
  final String primaryKeyColumn;
  
  /// Builder function that receives the record data and should return form widgets
  final Widget Function(BuildContext context, RecordData recordData) formBuilder;
  
  /// Widget to display when the record is not found
  final Widget? notFoundWidget;
  
  /// Widget to display while loading
  final Widget? loadingWidget;
  
  /// Widget to display on error
  final Widget Function(Object error)? errorBuilder;

  const ReactiveRecordForm({
    super.key,
    required this.dataAccess,
    required this.tableName,
    required this.primaryKey,
    required this.formBuilder,
    this.primaryKeyColumn = 'id',
    this.notFoundWidget,
    this.loadingWidget,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ReactiveRecordBuilder(
      dataAccess: dataAccess,
      tableName: tableName,
      primaryKey: primaryKey,
      primaryKeyColumn: primaryKeyColumn,
      loadingWidget: loadingWidget,
      errorBuilder: errorBuilder,
      builder: (context, recordData) {
        if (recordData == null) {
          return notFoundWidget ?? 
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Record not found', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
        }

        return formBuilder(context, recordData);
      },
    );
  }
}