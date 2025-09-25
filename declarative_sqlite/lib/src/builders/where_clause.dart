// lib/src/builders/where_clause.dart
import 'analysis_context.dart';
import 'query_column.dart';
import 'query_builder.dart';
import 'query_dependencies.dart';
import '../utils/value_serializer.dart';

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
  final QueryColumn _column;

  Condition(String columnExpression) : _column = QueryColumn.parse(columnExpression);
  
  QueryColumn get column => _column;

  Comparison eq(Object value) => _compare('=', value);
  Comparison neq(Object value) => _compare('!=', value);
  Comparison gt(Object value) => _compare('>', value);
  Comparison gte(Object value) => _compare('>=', value);
  Comparison lt(Object value) => _compare('<', value);
  Comparison lte(Object value) => _compare('<=', value);
  Comparison like(String value) => _compare('LIKE', value);
  InListComparison inList(List<Object> list) => InListComparison(column, list);
  InSubQueryComparsion inSubQuery(QueryBuilder subQuery) => InSubQueryComparsion(column, subQuery);
  Comparison get nil => _compare('IS NULL', null);
  Comparison get notNil => _compare('IS NOT NULL', null);

  Comparison _compare(String operator, Object? value) {
    return Comparison(_column, operator, value);
  }
}

class InSubQueryComparsion extends WhereClause {
  final QueryColumn column;
  final QueryBuilder subQuery;

  InSubQueryComparsion(this.column, this.subQuery);
  
  @override
  QueryDependencies analyzeDependencies(AnalysisContext context) {
    var dependencies = QueryDependencies.empty();
    
    // Analyze the column dependencies
    dependencies = dependencies.merge(column.analyzeDependencies(context));
    
    // Create a new context level for the subquery
    final subqueryContext = context.copy();
    subqueryContext.pushLevel();
    
    // Analyze the subquery dependencies
    dependencies = dependencies.merge(subQuery.analyzeDependencies(subqueryContext));
    
    return dependencies;
  }
  
  @override
  BuiltWhereClause build() {
    final (sql, parameters) = subQuery.build();
    
    return BuiltWhereClause(
      '${column.toSql()} IN ($sql)', 
      parameters
    );
  }
}

class InListComparison extends WhereClause {
  final QueryColumn column;
  final List<Object> list;

  InListComparison(this.column, this.list);
  
  @override
  BuiltWhereClause build() {
    final questionMarks = list.map((_) => '?').join(',');
    final serializedList = list.map(DatabaseValueSerializer.serialize).toList();
    return BuiltWhereClause('${column.toSql()} IN ($questionMarks)', serializedList);
  }

  @override
  QueryDependencies analyzeDependencies(AnalysisContext context) {
    var dependencies = QueryDependencies.empty();

    // Analyze the column dependencies
    dependencies = dependencies.merge(column.analyzeDependencies(context));

    return dependencies;
  }
}

class Comparison extends WhereClause {
  final QueryColumn column;
  final String operator;
  final Object? value;

  Comparison(this.column, this.operator, this.value);

  @override
  BuiltWhereClause build() {
    if (value == null && (operator == 'IS NULL' || operator == 'IS NOT NULL')) {
      return BuiltWhereClause('${column.toSql()} $operator', []);
    }
    
    // Check if value is a column reference (Condition object)
    if (value is Condition) {
      final condition = value as Condition;
      return BuiltWhereClause('${column.toSql()} $operator ${condition.column.toSql()}', []);
    }
    
    // Serialize values using the centralized database serialization logic
    final serializedValue = DatabaseValueSerializer.serialize(value);
    return BuiltWhereClause('${column.toSql()} $operator ?', [serializedValue]);
  }

  @override
  QueryDependencies analyzeDependencies(AnalysisContext context) {
    var dependencies = QueryDependencies.empty();
    
    // Analyze the left-hand column
    dependencies = dependencies.merge(column.analyzeDependencies(context));
    
    // Analyze the right-hand column if it's a column reference
    if (value is Condition) {
      final rightColumn = (value as Condition).column;
      dependencies = dependencies.merge(rightColumn.analyzeDependencies(context));
    }
    
    return dependencies;
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
