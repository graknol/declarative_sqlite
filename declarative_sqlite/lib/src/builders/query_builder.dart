import 'where_clause.dart';

class QueryBuilder {
  String? _from;
  final List<String> _columns = [];
  WhereClause? _where;
  final List<String> _orderBy = [];
  final List<String> _groupBy = [];
  final List<String> _joins = [];
  String? _having;

  QueryBuilder select(String column, [String? alias]) {
    if (alias != null) {
      _columns.add('$column AS $alias');
    } else {
      _columns.add(column);
    }
    return this;
  }

  QueryBuilder from(String table, [String? alias]) {
    if (alias != null) {
      _from = '$table AS $alias';
    } else {
      _from = table;
    }
    return this;
  }

  QueryBuilder where(WhereClause clause) {
    _where = clause;
    return this;
  }

  QueryBuilder orderBy(List<String> columns) {
    _orderBy.addAll(columns);
    return this;
  }

  QueryBuilder groupBy(List<String> columns) {
    _groupBy.addAll(columns);
    return this;
  }

  QueryBuilder having(String condition) {
    _having = condition;
    return this;
  }

  QueryBuilder join(String joinClause) {
    _joins.add(joinClause);
    return this;
  }

  QueryBuilder innerJoin(String table, String onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    _joins.add('INNER JOIN $tableWithAlias ON $onCondition');
    return this;
  }

  QueryBuilder leftJoin(String table, String onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    _joins.add('LEFT JOIN $tableWithAlias ON $onCondition');
    return this;
  }

  QueryBuilder rightJoin(String table, String onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    _joins.add('RIGHT JOIN $tableWithAlias ON $onCondition');
    return this;
  }

  QueryBuilder fullOuterJoin(String table, String onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    _joins.add('FULL OUTER JOIN $tableWithAlias ON $onCondition');
    return this;
  }

  QueryBuilder crossJoin(String table, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    _joins.add('CROSS JOIN $tableWithAlias');
    return this;
  }

  /// Select a subquery with an alias
  QueryBuilder selectSubQuery(void Function(QueryBuilder) build, String alias) {
    final subQueryBuilder = QueryBuilder();
    build(subQueryBuilder);
    final built = subQueryBuilder.build();
    final subQuery = built.$1;
    _columns.add('($subQuery) AS $alias');
    return this;
  }

  (String, List<Object?>) build() {
    if (_from == null) {
      throw StateError('A "from" clause is required to build a query.');
    }

    final columns = _columns.isEmpty ? '*' : _columns.join(', ');

    var sql = 'SELECT $columns FROM $_from';
    var parameters = <Object?>[];

    // Add JOINs
    if (_joins.isNotEmpty) {
      sql += ' ${_joins.join(' ')}';
    }

    if (_where != null) {
      final builtWhere = _where!.build();
      sql += ' WHERE ${builtWhere.sql}';
      parameters.addAll(builtWhere.parameters);
    }

    if (_groupBy.isNotEmpty) {
      sql += ' GROUP BY ${_groupBy.join(', ')}';
    }

    if (_having != null) {
      sql += ' HAVING $_having';
    }

    if (_orderBy.isNotEmpty) {
      sql += ' ORDER BY ${_orderBy.join(', ')}';
    }

    return (sql, parameters);
  }
}
