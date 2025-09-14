import 'package:meta/meta.dart';
import 'package:equatable/equatable.dart';
import 'expression_builder.dart';
import 'join_builder.dart';
import 'condition_builder.dart';
import 'data_access.dart';
import 'dynamic_record.dart';

/// Builder for constructing SQL SELECT queries with fluent syntax.
/// 
/// Supports SELECT expressions, FROM clause, JOINs, WHERE conditions,
/// GROUP BY, HAVING, ORDER BY, and LIMIT clauses.
@immutable
class QueryBuilder extends Equatable {
  QueryBuilder._({
    required this.selectExpressions,
    this.fromTable,
    this.fromAlias,
    required this.joins,
    this.whereConditionBuilder,
    required this.groupByColumns,
    this.havingConditionBuilder,
    required this.orderByColumns,
    this.limitCount,
    this.offsetCount,
  });

  /// Creates a new empty query builder
  QueryBuilder()
      : selectExpressions = const [],
        fromTable = null,
        fromAlias = null,
        joins = const [],
        whereConditionBuilder = null,
        groupByColumns = const [],
        havingConditionBuilder = null,
        orderByColumns = const [],
        limitCount = null,
        offsetCount = null;

  /// List of SELECT expressions
  final List<ExpressionBuilder> selectExpressions;

  /// The main table for the FROM clause
  final String? fromTable;

  /// Optional alias for the main table
  final String? fromAlias;

  /// List of JOIN clauses
  final List<JoinBuilder> joins;

  /// WHERE condition (composable support only)
  final ConditionBuilder? whereConditionBuilder;

  /// List of GROUP BY columns
  final List<String> groupByColumns;

  /// HAVING condition (composable support only)
  final ConditionBuilder? havingConditionBuilder;

  /// List of ORDER BY columns (with optional DESC/ASC)
  final List<String> orderByColumns;

  /// LIMIT count
  final int? limitCount;

  /// OFFSET count
  final int? offsetCount;

  /// Adds SELECT expressions
  QueryBuilder select(List<ExpressionBuilder> expressions) {
    return QueryBuilder._(
      selectExpressions: [...selectExpressions, ...expressions],
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereConditionBuilder: whereConditionBuilder,
      groupByColumns: groupByColumns,
      havingConditionBuilder: havingConditionBuilder,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Convenience method to select all columns
  QueryBuilder selectAll() {
    return select([Expressions.all]);
  }

  /// Convenience method to select specific columns
  QueryBuilder selectColumns(List<String> columnNames) {
    final expressions = columnNames.map((name) => ExpressionBuilder.column(name)).toList();
    return select(expressions);
  }

  /// Sets the FROM table
  QueryBuilder from(String tableName, [String? alias]) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: tableName,
      fromAlias: alias,
      joins: joins,
      whereConditionBuilder: whereConditionBuilder,
      groupByColumns: groupByColumns,
      havingConditionBuilder: havingConditionBuilder,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Adds a JOIN clause
  QueryBuilder join(JoinBuilder joinClause) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: [...joins, joinClause],
      whereConditionBuilder: whereConditionBuilder,
      groupByColumns: groupByColumns,
      havingConditionBuilder: havingConditionBuilder,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Convenience method for INNER JOIN
  QueryBuilder innerJoin(String tableName, String onCondition, [String? alias]) {
    var joinClause = Joins.inner(tableName).on(onCondition);
    if (alias != null) {
      joinClause = joinClause.as(alias);
    }
    return join(joinClause);
  }

  /// Convenience method for LEFT JOIN
  QueryBuilder leftJoin(String tableName, String onCondition, [String? alias]) {
    var joinClause = Joins.left(tableName).on(onCondition);
    if (alias != null) {
      joinClause = joinClause.as(alias);
    }
    return join(joinClause);
  }

  /// Sets the WHERE condition using ConditionBuilder
  QueryBuilder where(ConditionBuilder condition) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereConditionBuilder: condition,
      groupByColumns: groupByColumns,
      havingConditionBuilder: havingConditionBuilder,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Adds AND condition to existing WHERE clause using ConditionBuilder
  QueryBuilder andWhereCondition(ConditionBuilder condition) {
    final currentCondition = whereConditionBuilder;
    if (currentCondition != null) {
      return where(currentCondition.and(condition));
    } else {
      return where(condition);
    }
  }

  /// Adds OR condition to existing WHERE clause using ConditionBuilder
  QueryBuilder orWhereCondition(ConditionBuilder condition) {
    final currentCondition = whereConditionBuilder;
    if (currentCondition != null) {
      return where(currentCondition.or(condition));
    } else {
      return where(condition);
    }
  }

  /// Sets GROUP BY columns
  QueryBuilder groupBy(List<String> columnNames) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereConditionBuilder: whereConditionBuilder,
      groupByColumns: [...groupByColumns, ...columnNames],
      havingConditionBuilder: havingConditionBuilder,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Sets HAVING condition using ConditionBuilder
  QueryBuilder having(ConditionBuilder condition) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereConditionBuilder: whereConditionBuilder,
      groupByColumns: groupByColumns,
      havingConditionBuilder: condition,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Sets ORDER BY columns
  QueryBuilder orderBy(List<String> columnSpecs) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereConditionBuilder: whereConditionBuilder,
      groupByColumns: groupByColumns,
      havingConditionBuilder: havingConditionBuilder,
      orderByColumns: [...orderByColumns, ...columnSpecs],
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Convenience method to order by single column
  QueryBuilder orderByColumn(String columnName, [bool descending = false]) {
    final spec = descending ? '$columnName DESC' : columnName;
    return orderBy([spec]);
  }

  /// Sets LIMIT clause
  QueryBuilder limit(int count, [int? offset]) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereConditionBuilder: whereConditionBuilder,
      groupByColumns: groupByColumns,
      havingConditionBuilder: havingConditionBuilder,
      orderByColumns: orderByColumns,
      limitCount: count,
      offsetCount: offset ?? offsetCount,
    );
  }

  /// Sets OFFSET clause
  QueryBuilder offset(int count) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereConditionBuilder: whereConditionBuilder,
      groupByColumns: groupByColumns,
      havingConditionBuilder: havingConditionBuilder,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: count,
    );
  }

  /// Generates the SQL SELECT statement
  String toSql() {
    if (selectExpressions.isEmpty) {
      throw StateError('SELECT clause cannot be empty');
    }
    
    final buffer = StringBuffer();
    
    // SELECT clause
    buffer.write('SELECT ');
    buffer.write(selectExpressions.map((expr) => expr.toSql()).join(', '));
    
    // FROM clause
    if (fromTable != null) {
      buffer.write('\nFROM $fromTable');
      if (fromAlias != null) {
        buffer.write(' $fromAlias');
      }
    }
    
    // JOIN clauses
    for (final joinClause in joins) {
      buffer.write('\n${joinClause.toSql()}');
    }
    
    // WHERE clause 
    final whereClause = _buildWhereClause();
    if (whereClause != null) {
      buffer.write('\nWHERE $whereClause');
    }
    
    // GROUP BY clause
    if (groupByColumns.isNotEmpty) {
      buffer.write('\nGROUP BY ${groupByColumns.join(', ')}');
    }
    
    // HAVING clause
    final havingClause = _buildHavingClause();
    if (havingClause != null) {
      buffer.write('\nHAVING $havingClause');
    }
    
    // ORDER BY clause
    if (orderByColumns.isNotEmpty) {
      buffer.write('\nORDER BY ${orderByColumns.join(', ')}');
    }
    
    // LIMIT clause
    if (limitCount != null) {
      buffer.write('\nLIMIT $limitCount');
      if (offsetCount != null) {
        buffer.write(' OFFSET $offsetCount');
      }
    }
    
    return buffer.toString();
  }

  /// Builds the WHERE clause using condition builder
  String? _buildWhereClause() {
    if (whereConditionBuilder != null) {
      return whereConditionBuilder!.toSql();
    }
    return null;
  }

  /// Builds the HAVING clause using condition builder
  String? _buildHavingClause() {
    if (havingConditionBuilder != null) {
      return havingConditionBuilder!.toSql();
    }
    return null;
  }

  /// Gets all WHERE arguments in the correct order
  List<dynamic> getWhereArguments() {
    if (whereConditionBuilder != null) {
      return whereConditionBuilder!.getArguments();
    }
    return [];
  }

  /// Gets all HAVING arguments in the correct order
  List<dynamic> getHavingArguments() {
    if (havingConditionBuilder != null) {
      return havingConditionBuilder!.getArguments();
    }
    return [];
  }

  /// Gets all arguments for the query (WHERE + HAVING)
  List<dynamic> getAllArguments() {
    return [...getWhereArguments(), ...getHavingArguments()];
  }

  /// Execute this query and return a single record (or null)
  /// This method requires the query to have a FROM table specified
  Future<Map<String, dynamic>?> executeSingle(DataAccess dataAccess) async {
    if (fromTable == null) {
      throw StateError('FROM table must be specified to execute query');
    }
    
    final results = await executeMany(dataAccess);
    return results.isNotEmpty ? results.first : null;
  }

  /// Execute this query and return a list of records
  /// This method requires the query to have a FROM table specified
  Future<List<Map<String, dynamic>>> executeMany(DataAccess dataAccess) async {
    if (fromTable == null) {
      throw StateError('FROM table must be specified to execute query');
    }
    
    // For now, we support simple table queries without JOINs
    // Complex queries with JOINs would need raw SQL execution
    if (joins.isNotEmpty) {
      throw UnsupportedError('JOINs not yet supported in executeMany. Use simple table queries or implement raw SQL execution.');
    }
    
    // Extract WHERE clause and arguments
    final whereClause = _buildWhereClause();
    final whereArgs = getWhereArguments();
    
    // Build ORDER BY clause
    final orderByClause = orderByColumns.isNotEmpty ? orderByColumns.join(', ') : null;
    
    // For now, we ignore column selection since DataAccess.getAllWhere doesn't support it
    // In the future, this could be enhanced to support raw SQL queries
    
    return await dataAccess.getAllWhere(
      fromTable!,
      where: whereClause,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: orderByClause,
      limit: limitCount,
      offset: offsetCount,
    );
  }

  /// Execute this query and return a single DynamicRecord (or null)
  /// This provides ergonomic property-based access to column values
  Future<DynamicRecord?> executeDynamicSingle(DataAccess dataAccess) async {
    final result = await executeSingle(dataAccess);
    return result != null ? DynamicRecord(result) : null;
  }

  /// Execute this query and return a list of DynamicRecord instances
  /// This provides ergonomic property-based access to column values for each row
  Future<List<DynamicRecord>> executeDynamicMany(DataAccess dataAccess) async {
    final results = await executeMany(dataAccess);
    return results.map((row) => DynamicRecord(row)).toList();
  }
  static QueryBuilder table(String tableName) {
    return QueryBuilder().selectAll().from(tableName);
  }

  /// Create a query builder for a specific record by primary key
  static QueryBuilder byPrimaryKey(String tableName, dynamic primaryKey, {String primaryKeyColumn = 'id'}) {
    return QueryBuilder()
        .selectAll()
        .from(tableName)
        .where(ConditionBuilder.eq(primaryKeyColumn, primaryKey));
  }

  /// Create a query builder for all records in a table
  static QueryBuilder all(String tableName) {
    return QueryBuilder().selectAll().from(tableName);
  }

  @override
  String toString() => toSql();

  @override
  List<Object?> get props => [
        selectExpressions,
        fromTable,
        fromAlias,
        joins,
        whereConditionBuilder,
        groupByColumns,
        havingConditionBuilder,
        orderByColumns,
        limitCount,
        offsetCount,
      ];
}