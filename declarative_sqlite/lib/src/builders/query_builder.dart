import 'package:declarative_sqlite/src/builders/where_clause.dart';

class QueryBuilder {
  String? _from;
  final List<String> _columns = [];
  WhereClause? _where;
  final List<String> _orderBy = [];
  final List<String> _groupBy = [];

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

  (String, List<Object?>) build() {
    if (_from == null) {
      throw StateError('A "from" clause is required to build a query.');
    }

    final columns = _columns.isEmpty ? '*' : _columns.join(', ');

    var sql = 'SELECT $columns FROM $_from';
    var parameters = <Object?>[];

    if (_where != null) {
      final builtWhere = _where!.build();
      sql += ' WHERE ${builtWhere.sql}';
      parameters.addAll(builtWhere.parameters);
    }

    if (_groupBy.isNotEmpty) {
      sql += ' GROUP BY ${_groupBy.join(', ')}';
    }

    if (_orderBy.isNotEmpty) {
      sql += ' ORDER BY ${_orderBy.join(', ')}';
    }

    sql += ';';

    return (sql, parameters);
  }
}
