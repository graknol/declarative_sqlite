import 'package:meta/meta.dart';
import 'query_builder.dart';
import 'expression_builder.dart';

/// Builder for defining SQL VIEW specifications in a database schema.
/// 
/// Supports the fluent builder pattern for defining views with complex SELECT queries,
/// including subqueries, joins, expressions, aliases, and where clauses.
@immutable
class ViewBuilder {
  const ViewBuilder._({
    required this.name,
    required this.query,
  });

  /// Creates a new view builder with the specified name and query
  ViewBuilder(this.name, this.query);

  /// Creates a view from a raw SQL query string
  ViewBuilder.fromSql(this.name, String sqlQuery)
      : query = _RawQueryBuilder(sqlQuery);

  /// The view name
  final String name;

  /// The SELECT query that defines this view
  final dynamic query; // QueryBuilder or _RawQueryBuilder

  /// Creates a new view with the given query
  ViewBuilder withQuery(QueryBuilder newQuery) {
    return ViewBuilder._(
      name: name,
      query: newQuery,
    );
  }

  /// Creates a simple view that selects all columns from a table
  static ViewBuilder simple(String viewName, String tableName, [String? whereCondition]) {
    var query = QueryBuilder()
        .selectAll()
        .from(tableName);
    
    if (whereCondition != null) {
      query = query.where(whereCondition);
    }
    
    return ViewBuilder(viewName, query);
  }

  /// Creates a view with specific columns from a table
  static ViewBuilder withColumns(String viewName, String tableName, List<String> columns, [String? whereCondition]) {
    var query = QueryBuilder()
        .selectColumns(columns)
        .from(tableName);
    
    if (whereCondition != null) {
      query = query.where(whereCondition);
    }
    
    return ViewBuilder(viewName, query);
  }

  /// Creates a view with expressions and aliases
  static ViewBuilder withExpressions(String viewName, String tableName, List<ExpressionBuilder> expressions, [String? whereCondition]) {
    var query = QueryBuilder()
        .select(expressions)
        .from(tableName);
    
    if (whereCondition != null) {
      query = query.where(whereCondition);
    }
    
    return ViewBuilder(viewName, query);
  }

  /// Creates a view with joins
  static ViewBuilder withJoins(String viewName, QueryBuilder Function(QueryBuilder) queryBuilder) {
    final query = queryBuilder(QueryBuilder());
    return ViewBuilder(viewName, query);
  }

  /// Generates the SQL CREATE VIEW statement
  String toSql() {
    final buffer = StringBuffer();
    buffer.write('CREATE VIEW $name AS\n');
    
    if (query is QueryBuilder) {
      buffer.write((query as QueryBuilder).toSql());
    } else if (query is _RawQueryBuilder) {
      buffer.write((query as _RawQueryBuilder).sql);
    } else {
      throw StateError('Invalid query type for view "$name"');
    }
    
    return buffer.toString();
  }

  /// Generates the SQL DROP VIEW statement
  String dropSql() {
    return 'DROP VIEW IF EXISTS $name';
  }

  /// Gets the underlying query as a QueryBuilder if possible
  QueryBuilder? get queryBuilder {
    return query is QueryBuilder ? query as QueryBuilder : null;
  }

  /// Checks if this view uses a raw SQL query
  bool get isRawSql => query is _RawQueryBuilder;

  @override
  String toString() => toSql();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewBuilder &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          query == other.query;

  @override
  int get hashCode => name.hashCode ^ query.hashCode;
}

/// Internal class for raw SQL queries
class _RawQueryBuilder {
  const _RawQueryBuilder(this.sql);

  final String sql;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _RawQueryBuilder &&
          runtimeType == other.runtimeType &&
          sql == other.sql;

  @override
  int get hashCode => sql.hashCode;
}

/// Helper class for creating common view patterns
class Views {
  /// Creates a simple view that shows all rows from a table
  static ViewBuilder all(String viewName, String tableName) {
    return ViewBuilder.simple(viewName, tableName);
  }

  /// Creates a filtered view
  static ViewBuilder filtered(String viewName, String tableName, String whereCondition) {
    return ViewBuilder.simple(viewName, tableName, whereCondition);
  }

  /// Creates a view with specific columns
  static ViewBuilder columns(String viewName, String tableName, List<String> columns) {
    return ViewBuilder.withColumns(viewName, tableName, columns);
  }

  /// Creates a view with aggregated data
  static ViewBuilder aggregated(String viewName, String tableName, List<ExpressionBuilder> aggregates, List<String>? groupByColumns) {
    var query = QueryBuilder()
        .select(aggregates)
        .from(tableName);
    
    if (groupByColumns != null && groupByColumns.isNotEmpty) {
      query = query.groupBy(groupByColumns);
    }
    
    return ViewBuilder(viewName, query);
  }

  /// Creates a view with a join between two tables
  static ViewBuilder joined(String viewName, String leftTable, String rightTable, String onCondition, [List<ExpressionBuilder>? selectExpressions]) {
    var query = QueryBuilder()
        .from(leftTable)
        .innerJoin(rightTable, onCondition);
    
    if (selectExpressions != null) {
      query = query.select(selectExpressions);
    } else {
      query = query.selectAll();
    }
    
    return ViewBuilder(viewName, query);
  }

  /// Creates a view from raw SQL
  static ViewBuilder fromSql(String viewName, String sqlQuery) {
    return ViewBuilder.fromSql(viewName, sqlQuery);
  }
}