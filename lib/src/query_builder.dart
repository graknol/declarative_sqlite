import 'package:meta/meta.dart';
import 'expression_builder.dart';
import 'join_builder.dart';

/// Builder for constructing SQL SELECT queries with fluent syntax.
/// 
/// Supports SELECT expressions, FROM clause, JOINs, WHERE conditions,
/// GROUP BY, HAVING, ORDER BY, and LIMIT clauses.
@immutable
class QueryBuilder {
  const QueryBuilder._({
    required this.selectExpressions,
    this.fromTable,
    this.fromAlias,
    required this.joins,
    this.whereCondition,
    required this.groupByColumns,
    this.havingCondition,
    required this.orderByColumns,
    this.limitCount,
    this.offsetCount,
  });

  /// Creates a new empty query builder
  const QueryBuilder()
      : selectExpressions = const [],
        fromTable = null,
        fromAlias = null,
        joins = const [],
        whereCondition = null,
        groupByColumns = const [],
        havingCondition = null,
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

  /// WHERE condition
  final String? whereCondition;

  /// List of GROUP BY columns
  final List<String> groupByColumns;

  /// HAVING condition
  final String? havingCondition;

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
      whereCondition: whereCondition,
      groupByColumns: groupByColumns,
      havingCondition: havingCondition,
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
      whereCondition: whereCondition,
      groupByColumns: groupByColumns,
      havingCondition: havingCondition,
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
      whereCondition: whereCondition,
      groupByColumns: groupByColumns,
      havingCondition: havingCondition,
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

  /// Sets the WHERE condition
  QueryBuilder where(String condition) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereCondition: condition,
      groupByColumns: groupByColumns,
      havingCondition: havingCondition,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Adds AND condition to existing WHERE clause
  QueryBuilder andWhere(String condition) {
    final newCondition = whereCondition != null
        ? '($whereCondition) AND ($condition)'
        : condition;
    return where(newCondition);
  }

  /// Adds OR condition to existing WHERE clause
  QueryBuilder orWhere(String condition) {
    final newCondition = whereCondition != null
        ? '($whereCondition) OR ($condition)'
        : condition;
    return where(newCondition);
  }

  /// Sets GROUP BY columns
  QueryBuilder groupBy(List<String> columnNames) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereCondition: whereCondition,
      groupByColumns: [...groupByColumns, ...columnNames],
      havingCondition: havingCondition,
      orderByColumns: orderByColumns,
      limitCount: limitCount,
      offsetCount: offsetCount,
    );
  }

  /// Sets HAVING condition
  QueryBuilder having(String condition) {
    return QueryBuilder._(
      selectExpressions: selectExpressions,
      fromTable: fromTable,
      fromAlias: fromAlias,
      joins: joins,
      whereCondition: whereCondition,
      groupByColumns: groupByColumns,
      havingCondition: condition,
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
      whereCondition: whereCondition,
      groupByColumns: groupByColumns,
      havingCondition: havingCondition,
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
      whereCondition: whereCondition,
      groupByColumns: groupByColumns,
      havingCondition: havingCondition,
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
      whereCondition: whereCondition,
      groupByColumns: groupByColumns,
      havingCondition: havingCondition,
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
    if (whereCondition != null) {
      buffer.write('\nWHERE $whereCondition');
    }
    
    // GROUP BY clause
    if (groupByColumns.isNotEmpty) {
      buffer.write('\nGROUP BY ${groupByColumns.join(', ')}');
    }
    
    // HAVING clause
    if (havingCondition != null) {
      buffer.write('\nHAVING $havingCondition');
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

  @override
  String toString() => toSql();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryBuilder &&
          runtimeType == other.runtimeType &&
          _listEquals(selectExpressions, other.selectExpressions) &&
          fromTable == other.fromTable &&
          fromAlias == other.fromAlias &&
          _listEquals(joins, other.joins) &&
          whereCondition == other.whereCondition &&
          _listEquals(groupByColumns, other.groupByColumns) &&
          havingCondition == other.havingCondition &&
          _listEquals(orderByColumns, other.orderByColumns) &&
          limitCount == other.limitCount &&
          offsetCount == other.offsetCount;

  @override
  int get hashCode =>
      selectExpressions.hashCode ^
      fromTable.hashCode ^
      fromAlias.hashCode ^
      joins.hashCode ^
      whereCondition.hashCode ^
      groupByColumns.hashCode ^
      havingCondition.hashCode ^
      orderByColumns.hashCode ^
      limitCount.hashCode ^
      offsetCount.hashCode;

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}