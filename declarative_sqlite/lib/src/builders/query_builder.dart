import 'package:equatable/equatable.dart';
import 'where_clause.dart';

class QueryBuilder extends Equatable {
  String? _from;
  final List<String> _columns = [];
  WhereClause? _where;
  final List<String> _orderBy = [];
  final List<String> _groupBy = [];
  final List<String> _joins = [];
  final List<Object?> _joinParameters = [];
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

  QueryBuilder innerJoin(String table, dynamic onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final conditionSql = _buildJoinCondition(onCondition);
    _joins.add('INNER JOIN $tableWithAlias ON $conditionSql');
    return this;
  }

  QueryBuilder leftJoin(String table, dynamic onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final conditionSql = _buildJoinCondition(onCondition);
    _joins.add('LEFT JOIN $tableWithAlias ON $conditionSql');
    return this;
  }

  QueryBuilder rightJoin(String table, dynamic onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final conditionSql = _buildJoinCondition(onCondition);
    _joins.add('RIGHT JOIN $tableWithAlias ON $conditionSql');
    return this;
  }

  QueryBuilder fullOuterJoin(String table, dynamic onCondition, [String? alias]) {
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final conditionSql = _buildJoinCondition(onCondition);
    _joins.add('FULL OUTER JOIN $tableWithAlias ON $conditionSql');
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

  /// Helper method to build join conditions
  String _buildJoinCondition(dynamic onCondition) {
    if (onCondition is String) {
      return onCondition;
    } else if (onCondition is WhereClause) {
      final built = onCondition.build();
      _joinParameters.addAll(built.parameters);
      return built.sql;
    } else {
      throw ArgumentError('Join condition must be either a String or WhereClause');
    }
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
      parameters.addAll(_joinParameters);
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

  /// Gets the main table name being queried (without alias).
  String? get tableName {
    if (_from == null) return null;
    // Handle "table AS alias" format
    final parts = _from!.split(' ');
    return parts.first;
  }

  @override
  List<Object?> get props => [
        _from,
        _columns,
        _where,
        _orderBy,
        _groupBy,
        _joins,
        _joinParameters,
        _having,
      ];
}
