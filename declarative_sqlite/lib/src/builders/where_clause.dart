// lib/src/builders/where_clause.dart
import 'package:declarative_sqlite/src/builders/query_builder.dart';

abstract class WhereClause {
  BuiltWhereClause build();
}

class BuiltWhereClause {
  final String sql;
  final List<Object?> parameters;

  BuiltWhereClause(this.sql, this.parameters);
}

class Condition {
  final String _column;

  Condition(this._column);

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
    return BuiltWhereClause('$column $operator ?', [value]);
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
