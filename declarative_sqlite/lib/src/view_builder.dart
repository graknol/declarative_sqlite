import 'package:meta/meta.dart';
import 'query_builder.dart';
import 'expression_builder.dart';
import 'condition_builder.dart';

/// Builder for defining SQL VIEW specifications in a database schema.
/// 
/// Provides a unified fluent API for creating views with any complexity level,
/// from simple table filters to complex multi-table joins and aggregations.
/// 
/// ## Usage Examples
/// ```dart
/// // Simple view from table (all columns)
/// ViewBuilder.create('all_users')
///   .fromTable('users')
/// 
/// // Filtered view
/// ViewBuilder.create('active_users')
///   .fromTable('users', whereCondition: 'active = 1')
/// 
/// // View with specific columns
/// ViewBuilder.create('user_summary')
///   .fromTable('users', columns: ['id', 'username', 'email'])
/// 
/// // View with expressions and aliases
/// ViewBuilder.create('user_enhanced')
///   .fromTable('users', expressions: [
///     ExpressionBuilder.column('id'),
///     ExpressionBuilder.function('UPPER', ['username']).as('name')
///   ])
/// 
/// // Complex view with query builder
/// ViewBuilder.create('user_stats')
///   .fromQuery((query) => query
///     .select([...])
///     .from('users', 'u')
///     .leftJoin('posts', 'u.id = p.user_id', 'p')
///     .groupBy(['u.id']))
/// 
/// // Raw SQL for complex cases
/// ViewBuilder.create('custom_view')
///   .fromSql('SELECT * FROM users WHERE age > 18')
/// ```
@immutable
class ViewBuilder {
  const ViewBuilder._({
    required this.name,
    required this.query,
  });

  /// The view name
  final String name;

  /// The SELECT query that defines this view
  final dynamic query; // QueryBuilder or _RawQueryBuilder

  /// Creates a new view builder with the specified name.
  /// This is the single entry point for creating any type of view.
  factory ViewBuilder.create(String viewName) {
    return _ViewBuilderStep1._(viewName);
  }

  /// Creates a view builder with a pre-built query (for internal use)
  ViewBuilder._withQuery(this.name, this.query);

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

  // Legacy factory methods for backward compatibility
  // TODO: Mark as deprecated in a future release
  
  /// Creates a simple view that selects all columns from a table
  static ViewBuilder simple(String viewName, String tableName, [ConditionBuilder? whereCondition]) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromTable(tableName, whereCondition: whereCondition);
  }

  /// Creates a view with specific columns from a table
  static ViewBuilder withColumns(String viewName, String tableName, List<String> columns, [ConditionBuilder? whereCondition]) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromTable(tableName, columns: columns, whereCondition: whereCondition);
  }

  /// Creates a view with expressions and aliases
  static ViewBuilder withExpressions(String viewName, String tableName, List<ExpressionBuilder> expressions, [ConditionBuilder? whereCondition]) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromTable(tableName, expressions: expressions, whereCondition: whereCondition);
  }

  /// Creates a view with joins
  static ViewBuilder withJoins(String viewName, QueryBuilder Function(QueryBuilder) queryBuilder) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromQuery(queryBuilder);
  }

  /// Creates a view from a raw SQL query string
  static ViewBuilder fromSql(String viewName, String sqlQuery) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromSql(sqlQuery);
  }
}

/// First step in the fluent builder - choose the data source
class _ViewBuilderStep1 extends ViewBuilder {
  _ViewBuilderStep1._(String name) : super._withQuery(name, null);

  /// Define the view based on a single table
  /// 
  /// You can specify columns to select, expressions with aliases, 
  /// and an optional WHERE condition.
  ViewBuilder fromTable(
    String tableName, {
    List<String>? columns,
    List<ExpressionBuilder>? expressions,
    ConditionBuilder? whereCondition,
  }) {
    QueryBuilder query;
    
    if (expressions != null) {
      query = QueryBuilder().select(expressions);
    } else if (columns != null) {
      query = QueryBuilder().selectColumns(columns);
    } else {
      query = QueryBuilder().selectAll();
    }
    
    query = query.from(tableName);
    
    if (whereCondition != null) {
      query = query.where(whereCondition);
    }
    
    return ViewBuilder._withQuery(name, query);
  }

  /// Define the view using a custom query builder function
  /// 
  /// This allows you to create complex views with joins, aggregations,
  /// subqueries, and any other SQL features supported by QueryBuilder.
  ViewBuilder fromQuery(QueryBuilder Function(QueryBuilder) queryBuilder) {
    final query = queryBuilder(QueryBuilder());
    return ViewBuilder._withQuery(name, query);
  }

  /// Define the view using raw SQL
  /// 
  /// Use this for complex queries that cannot be expressed with QueryBuilder,
  /// such as window functions, CTEs, or database-specific features.
  ViewBuilder fromSql(String sqlQuery) {
    return ViewBuilder._withQuery(name, _RawQueryBuilder(sqlQuery));
  }
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

/// Helper class for creating common view patterns.
/// 
/// **Note**: This class is maintained for backward compatibility.
/// For new code, prefer using `ViewBuilder.create(name).fromTable(...)` 
/// or other `ViewBuilder.create(...)` methods for a more consistent API.
class Views {
  /// Creates a simple view that shows all rows from a table
  static ViewBuilder all(String viewName, String tableName) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromTable(tableName);
  }

  /// Creates a filtered view
  static ViewBuilder filtered(String viewName, String tableName, ConditionBuilder whereCondition) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromTable(tableName, whereCondition: whereCondition);
  }

  /// Creates a view with specific columns
  static ViewBuilder columns(String viewName, String tableName, List<String> columns) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromTable(tableName, columns: columns);
  }

  /// Creates a view with aggregated data
  static ViewBuilder aggregated(String viewName, String tableName, List<ExpressionBuilder> aggregates, List<String>? groupByColumns) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromQuery((query) {
      var q = query.select(aggregates).from(tableName);
      if (groupByColumns != null && groupByColumns.isNotEmpty) {
        q = q.groupBy(groupByColumns);
      }
      return q;
    });
  }

  /// Creates a view with a join between two tables
  static ViewBuilder joined(String viewName, String leftTable, String rightTable, String onCondition, [List<ExpressionBuilder>? selectExpressions]) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromQuery((query) {
      var q = query.from(leftTable).innerJoin(rightTable, onCondition);
      if (selectExpressions != null) {
        q = q.select(selectExpressions);
      } else {
        q = q.selectAll();
      }
      return q;
    });
  }

  /// Creates a view from raw SQL
  static ViewBuilder fromSql(String viewName, String sqlQuery) {
    return (ViewBuilder.create(viewName) as _ViewBuilderStep1).fromSql(sqlQuery);
  }
}