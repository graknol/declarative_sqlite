import 'query_builder.dart';
import 'where_clause.dart';
import '../schema/view.dart';

class ViewBuilder {
  final String name;
  final StringBuffer _definition = StringBuffer();

  ViewBuilder(this.name);

  ViewBuilder select(String expression, [String? alias]) {
    if (_definition.isEmpty) {
      _definition.write('SELECT ');
    } else {
      _definition.write(', ');
    }
    _definition.write(expression);
    if (alias != null) {
      _definition.write(' AS $alias');
    }
    return this;
  }

  ViewBuilder selectSubQuery(
      void Function(QueryBuilder) callback, String alias) {
    if (_definition.isEmpty) {
      _definition.write('SELECT ');
    } else {
      _definition.write(', ');
    }
    
    final subQueryBuilder = QueryBuilder();
    callback(subQueryBuilder);
    final built = subQueryBuilder.build();
    final subQuery = built.$1;
    
    _definition.write('($subQuery) AS $alias');
    return this;
  }

  ViewBuilder from(String table, [String? alias]) {
    _definition.write(' FROM $table');
    if (alias != null) {
      _definition.write(' AS $alias');
    }
    return this;
  }

  ViewBuilder fromSubQuery(
    void Function(QueryBuilder) build, [
    String? alias,
  ]) {
    final subQueryBuilder = QueryBuilder();
    build(subQueryBuilder);
    final built = subQueryBuilder.build();
    final subQuery = built.$1;

    _definition.write(' FROM ($subQuery)');
    if (alias != null) {
      _definition.write(' AS $alias');
    }
    return this;
  }

  ViewBuilder join(String joinClause) {
    _definition.write(' $joinClause');
    return this;
  }

  ViewBuilder innerJoin(String table, dynamic onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final conditionSql = _buildJoinCondition(onCondition);
    _definition.write(' INNER JOIN $tableWithAlias ON $conditionSql');
    return this;
  }

  ViewBuilder leftJoin(String table, dynamic onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final conditionSql = _buildJoinCondition(onCondition);
    _definition.write(' LEFT JOIN $tableWithAlias ON $conditionSql');
    return this;
  }

  ViewBuilder rightJoin(String table, dynamic onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final conditionSql = _buildJoinCondition(onCondition);
    _definition.write(' RIGHT JOIN $tableWithAlias ON $conditionSql');
    return this;
  }

  ViewBuilder fullOuterJoin(String table, dynamic onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final conditionSql = _buildJoinCondition(onCondition);
    _definition.write(' FULL OUTER JOIN $tableWithAlias ON $conditionSql');
    return this;
  }

  ViewBuilder crossJoin(String table, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    _definition.write(' CROSS JOIN $tableWithAlias');
    return this;
  }

  ViewBuilder where(WhereClause condition) {
    final builtWhere = condition.build();
    _definition.write(' WHERE ${builtWhere.sql}');
    return this;
  }

  ViewBuilder groupBy(List<String> columns) {
    _definition.write(' GROUP BY ${columns.join(', ')}');
    return this;
  }

  ViewBuilder having(String condition) {
    _definition.write(' HAVING $condition');
    return this;
  }

  ViewBuilder orderBy(List<String> columns) {
    _definition.write(' ORDER BY ${columns.join(', ')}');
    return this;
  }

  /// Helper method to build join conditions
  String _buildJoinCondition(dynamic onCondition) {
    if (onCondition is String) {
      return onCondition;
    } else if (onCondition is WhereClause) {
      final built = onCondition.build();
      return built.sql;
    } else {
      throw ArgumentError('Join condition must be either a String or WhereClause');
    }
  }

  View build() {
    return View(name: name, definition: _definition.toString());
  }
}
