import 'aliased.dart';
import 'analysis_context.dart';
import 'column.dart';
import 'join_clause.dart';
import 'query_dependencies.dart';
import 'where_clause.dart';

class QueryBuilder {
  Aliased<String>? _from;
  final List<Aliased<Column>> _columns = [];
  WhereClause? _where;
  final List<Column> _orderBy = [];
  final List<Column> _groupBy = [];
  final List<JoinClause> _joins = [];
  String? _having;
  String? _updateTable; // Table to target for CRUD operations

  QueryBuilder select(String column, [String? alias]) {
    _columns.add(Aliased(Column.parse(column), alias));
    return this;
  }

  QueryBuilder from(String table, [String? alias]) {
    _from = Aliased(table, alias);
    return this;
  }

  QueryBuilder where(WhereClause clause) {
    _where = clause;
    return this;
  }

  QueryBuilder orderBy(List<String> columns) {
    _orderBy.addAll(columns.map((col) => Column.parse(col)));
    return this;
  }

  QueryBuilder groupBy(List<String> columns) {
    _groupBy.addAll(columns.map((col) => Column.parse(col)));
    return this;
  }

  QueryBuilder having(String condition) {
    _having = condition;
    return this;
  }

  /// Specifies that results from this query should be CRUD-enabled
  /// targeting the specified table for update operations.
  ///
  /// This allows queries from views or joins to return updatable records
  /// as long as they include system_id and system_version from the target table.
  QueryBuilder forUpdate(String tableName) {
    _updateTable = tableName;
    return this;
  }

  QueryBuilder innerJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    _joins.add(JoinClause.inner(table, onCondition, alias));
    return this;
  }

  QueryBuilder leftJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    _joins.add(JoinClause.left(table, onCondition, alias));
    return this;
  }

  QueryBuilder rightJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    _joins.add(JoinClause.right(table, onCondition, alias));
    return this;
  }

  QueryBuilder fullOuterJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    _joins.add(JoinClause.fullOuter(table, onCondition, alias));
    return this;
  }

  QueryBuilder crossJoin(
    String table,[
    String? alias,
  ]) {
    _joins.add(JoinClause.cross(table, alias));
    return this;
  }

  /// Select a subquery with an alias
  QueryBuilder selectSubQuery(void Function(QueryBuilder) build, String alias) {
    final subQueryBuilder = QueryBuilder();
    build(subQueryBuilder);
    final built = subQueryBuilder.build();
    final subQuery = built.$1;
    _columns.add(Aliased(Column.parse('($subQuery)'), alias));
    return this;
  }



  (String, List<Object?>) build() {
    if (_from == null) {
      throw StateError('A "from" clause is required to build a query.');
    }

    final columns = _columns.isEmpty
        ? '*'
        : _columns.map((col) => col.toString()).join(', ');

    var sql = 'SELECT $columns FROM ${_from!.toString()}';
    var parameters = <Object?>[];

    // Add JOINs using structured JoinClause.build()
    for (final joinClause in _joins) {
      final builtJoin = joinClause.build();
      sql += ' ${builtJoin.sql}';
      parameters.addAll(builtJoin.parameters);
    }

    if (_where != null) {
      final builtWhere = _where!.build();
      sql += ' WHERE ${builtWhere.sql}';
      parameters.addAll(builtWhere.parameters);
    }

    if (_groupBy.isNotEmpty) {
      sql += ' GROUP BY ${_groupBy.map((col) => col.toSql()).join(', ')}';
    }

    if (_having != null) {
      sql += ' HAVING $_having';
    }

    if (_orderBy.isNotEmpty) {
      sql += ' ORDER BY ${_orderBy.map((col) => col.toSql()).join(', ')}';
    }

    if (_limit != null) {
      sql += ' LIMIT $_limit';
    }

    if (_offset != null) {
      sql += ' OFFSET $_offset';
    }

    return (sql, parameters);
  }

  /// Gets the main table name being queried (without alias).
  String? get tableName {
    if (_from == null) return null;
    return _from!.expression;
  }

  /// Gets the table name specified for CRUD operations via forUpdate()
  String? get updateTableName => _updateTable;

  int? _limit;
  int? _offset;

  QueryBuilder limit(int count) {
    _limit = count;
    return this;
  }

  QueryBuilder offset(int count) {
    _offset = count;
    return this;
  }

  /// Analyzes this query to determine table and column dependencies
  QueryDependencies analyzeDependencies([AnalysisContext? parentContext]) {
    final context = parentContext ?? AnalysisContext();
    var dependencies = QueryDependencies.empty();

    // Build the analysis context with FROM clause
    String? baseTableName;

    // Add FROM clause to context
    if (_from != null) {
      baseTableName = _from!.expression;
      context.addTable(baseTableName, alias: _from!.alias);

      // Add to dependencies with alias if present
      final tableRef = _from!.alias != null
          ? '${_from!.expression} AS ${_from!.alias}'
          : _from!.expression;

      dependencies = dependencies.merge(QueryDependencies(
        tables: {tableRef},
        columns: <QueryDependencyColumn>{},
        usesWildcard: false,
      ));
    }

    // Add JOIN clauses and analyze their dependencies
    for (final joinClause in _joins) {
      dependencies = dependencies.merge(joinClause.analyzeDependencies(context));
    }

    // Analyze columns from SELECT clause using Column.analyzeDependencies
    for (final col in _columns) {
      dependencies = dependencies.merge(col.expression.analyzeDependencies(context, baseTableName));
    }

    // Add dependencies from WHERE clause
    if (_where != null) {
      dependencies = dependencies.merge(_where!.analyzeDependencies(context));
    }

    // Analyze columns from ORDER BY clause
    for (final columnExpr in _orderBy) {
      dependencies = dependencies.merge(columnExpr.analyzeDependencies(context, baseTableName));
    }

    // Analyze columns from GROUP BY clause
    for (final columnExpr in _groupBy) {
      dependencies = dependencies.merge(columnExpr.analyzeDependencies(context, baseTableName));
    }

    // Note: HAVING clause analysis would require WhereClause type
    // Currently _having is a String, so we can't analyze it structurally

    return dependencies;
  }
}
