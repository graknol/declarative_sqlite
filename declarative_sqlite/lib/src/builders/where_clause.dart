// lib/src/builders/where_clause.dart
import 'analysis_context.dart';
import 'query_builder.dart';
import 'query_dependencies.dart';

abstract class WhereClause {
  BuiltWhereClause build();
  
  /// Analyzes this WHERE clause to extract table and column dependencies
  QueryDependencies analyzeDependencies(AnalysisContext context);
}

class BuiltWhereClause {
  final String sql;
  final List<Object?> parameters;

  BuiltWhereClause(this.sql, this.parameters);
}

class Condition {
  final String _column;

  Condition(this._column);
  
  String get column => _column;

  Comparison eq(Object value) => _compare('=', value);
  Comparison neq(Object value) => _compare('!=', value);
  Comparison gt(Object value) => _compare('>', value);
  Comparison gte(Object value) => _compare('>=', value);
  Comparison lt(Object value) => _compare('<', value);
  Comparison lte(Object value) => _compare('<=', value);
  Comparison like(String value) => _compare('LIKE', value);
  Comparison get nil => _compare('IS NULL', null);
  Comparison get notNil => _compare('IS NOT NULL', null);

  Comparison _compare(String operator, Object? value) {
    return Comparison(_column, operator, value);
  }
}

class Comparison extends WhereClause {
  final String column;
  final String operator;
  final Object? value;

  Comparison(this.column, this.operator, this.value);

  @override
  BuiltWhereClause build() {
    if (value == null && (operator == 'IS NULL' || operator == 'IS NOT NULL')) {
      return BuiltWhereClause('$column $operator', []);
    }
    
    // Check if value is a column reference (Condition object)
    if (value is Condition) {
      final condition = value as Condition;
      return BuiltWhereClause('$column $operator ${condition.column}', []);
    }
    
    return BuiltWhereClause('$column $operator ?', [value]);
  }

  @override
  QueryDependencies analyzeDependencies(AnalysisContext context) {
    final columns = <QueryDependencyColumn>{};
    
    // Add the left-hand column
    if (column.contains('.')) {
      // Already qualified (table.column or alias.column)
      final parts = column.split('.');
      final tableOrAlias = parts[0];
      final columnName = parts[1];
      
      // Resolve the table/alias to get the full table name
      final resolvedTable = context.resolveTable(tableOrAlias) ?? tableOrAlias;
      columns.add(QueryDependencyColumn(resolvedTable, columnName));
    } else {
      // Unqualified column - use primary table from context
      final primaryTable = context.primaryTable ?? '';
      columns.add(QueryDependencyColumn(primaryTable, column));
    }
    
    // Add the right-hand column if it's a column reference
    if (value is Condition) {
      final rightColumn = (value as Condition).column;
      if (rightColumn.contains('.')) {
        final parts = rightColumn.split('.');
        final tableOrAlias = parts[0];
        final columnName = parts[1];
        
        final resolvedTable = context.resolveTable(tableOrAlias) ?? tableOrAlias;
        columns.add(QueryDependencyColumn(resolvedTable, columnName));
      } else {
        final primaryTable = context.primaryTable ?? '';
        columns.add(QueryDependencyColumn(primaryTable, rightColumn));
      }
    }
    
    return QueryDependencies(
      tables: <String>{}, // Tables will be inferred from columns
      columns: columns,
      usesWildcard: false,
    );
  }
}

class LogicalOperator extends WhereClause {
  final String operator;
  final List<WhereClause> clauses;

  LogicalOperator(this.operator, this.clauses);

  @override
  BuiltWhereClause build() {
    if (clauses.isEmpty) {
      return BuiltWhereClause('', []);
    }
    final builtClauses = clauses.map((c) => c.build()).toList();
    final sql = '(${builtClauses.map((c) => c.sql).join(' $operator ')})';
    final parameters = builtClauses.expand((c) => c.parameters).toList();
    return BuiltWhereClause(sql, parameters);
  }

  @override
  QueryDependencies analyzeDependencies(AnalysisContext context) {
    var result = QueryDependencies.empty();
    
    // Merge dependencies from all child clauses
    for (final clause in clauses) {
      result = result.merge(clause.analyzeDependencies(context));
    }
    
    return result;
  }
}

Condition col(String column) => Condition(column);
LogicalOperator and(List<WhereClause> clauses) =>
    LogicalOperator('AND', clauses);
LogicalOperator or(List<WhereClause> clauses) => LogicalOperator('OR', clauses);

class Exists extends WhereClause {
  final QueryBuilder _subQuery;
  final bool _negated;

  Exists(this._subQuery, [this._negated = false]);

  @override
  BuiltWhereClause build() {
    final builtSubQuery = _subQuery.build();
    final subQuerySql = builtSubQuery.$1;
    final subQueryParameters = builtSubQuery.$2;
    final operator = _negated ? 'NOT EXISTS' : 'EXISTS';
    return BuiltWhereClause(
        '$operator ($subQuerySql)', subQueryParameters);
  }

  @override
  QueryDependencies analyzeDependencies(AnalysisContext context) {
    // Create a new context level for the subquery
    final subqueryContext = context.copy();
    subqueryContext.pushLevel();
    
    // Delegate to the subquery's dependency analysis
    return _subQuery.analyzeDependencies(subqueryContext);
  }
}

Exists exists(void Function(QueryBuilder) build) {
  final builder = QueryBuilder();
  build(builder);
  return Exists(builder);
}

Exists notExists(void Function(QueryBuilder) build) {
  final builder = QueryBuilder();
  build(builder);
  return Exists(builder, true);
}

class RawSqlWhereClause extends WhereClause {
  final String sql;
  final List<Object?>? parameters;

  RawSqlWhereClause(this.sql, [this.parameters]);

  @override
  BuiltWhereClause build() {
    return BuiltWhereClause(sql, parameters ?? []);
  }

  @override
  QueryDependencies analyzeDependencies(AnalysisContext context) {
    // For raw SQL, we can't analyze dependencies without parsing
    // This is a limitation that encourages use of structured queries
    return QueryDependencies.empty();
  }
}
