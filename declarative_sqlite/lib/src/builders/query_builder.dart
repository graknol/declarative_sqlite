import 'aliased.dart';
import 'analysis_context.dart';
import 'join_clause.dart';
import 'query_dependencies.dart';
import 'where_clause.dart';

class QueryBuilder {
  Aliased<String>? _from;
  final List<Aliased<String>> _columns = [];
  WhereClause? _where;
  final List<String> _orderBy = [];
  final List<String> _groupBy = [];
  final List<JoinClause> _joins = [];
  String? _having;
  String? _updateTable; // Table to target for CRUD operations

  QueryBuilder select(String column, [String? alias]) {
    _columns.add(Aliased(column, alias));
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

  /// Specifies that results from this query should be CRUD-enabled
  /// targeting the specified table for update operations.
  ///
  /// This allows queries from views or joins to return updatable records
  /// as long as they include system_id and system_version from the target table.
  QueryBuilder forUpdate(String tableName) {
    _updateTable = tableName;
    return this;
  }

  QueryBuilder _join(
    String type,
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    _joins.add(JoinClause(type, Aliased<String>(table, alias), onCondition));
    return this;
  }

  QueryBuilder innerJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    return _join('INNER', table, onCondition, alias);
  }

  QueryBuilder leftJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    return _join('LEFT', table, onCondition, alias);
  }

  QueryBuilder rightJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    return _join('RIGHT', table, onCondition, alias);
  }

  QueryBuilder fullOuterJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    return _join('FULL OUTER', table, onCondition, alias);
  }

  QueryBuilder crossJoin(
    String table,
    WhereClause onCondition, [
    String? alias,
  ]) {
    return _join('CROSS', table, onCondition, alias);
  }

  /// Select a subquery with an alias
  QueryBuilder selectSubQuery(void Function(QueryBuilder) build, String alias) {
    final subQueryBuilder = QueryBuilder();
    build(subQueryBuilder);
    final built = subQueryBuilder.build();
    final subQuery = built.$1;
    _columns.add(Aliased('($subQuery)', alias));
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
      sql += ' GROUP BY ${_groupBy.map((col) => col.toString()).join(', ')}';
    }

    if (_having != null) {
      sql += ' HAVING $_having';
    }

    if (_orderBy.isNotEmpty) {
      sql += ' ORDER BY ${_orderBy.map((col) => col.toString()).join(', ')}';
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

    // Check for wildcard in SELECT columns
    bool hasWildcard = _columns
        .any((col) => col.expression == '*' || col.expression.contains('.*'));

    // Add columns from SELECT clause
    final selectedColumns = <QueryDependencyColumn>{};
    for (final col in _columns) {
      if (col.expression != '*' && !col.expression.contains('.*')) {
        final columnExpr = col.expression;
        if (columnExpr.contains('.')) {
          // Qualified column (table.column or alias.column)
          final parts = columnExpr.split('.');
          final tableOrAlias = parts[0];
          final columnName = parts[1];

          // Resolve the table/alias to get the full table name
          final resolvedTable =
              context.resolveTable(tableOrAlias) ?? tableOrAlias;
          selectedColumns.add(QueryDependencyColumn(resolvedTable, columnName));
        } else if (baseTableName != null) {
          // Unqualified column - use base table
          selectedColumns.add(QueryDependencyColumn(baseTableName, columnExpr));
        }
      }
    }

    dependencies = dependencies.merge(QueryDependencies(
      tables: <String>{},
      columns: selectedColumns,
      usesWildcard: hasWildcard,
    ));

    // Add dependencies from WHERE clause
    if (_where != null) {
      dependencies = dependencies.merge(_where!.analyzeDependencies(context));
    }

    // Add columns from ORDER BY clause
    final orderByColumns = <QueryDependencyColumn>{};
    for (final columnExpr in _orderBy) {
      if (columnExpr.contains('.')) {
        // Qualified column (table.column or alias.column)
        final parts = columnExpr.split('.');
        final tableOrAlias = parts[0];
        final columnName = parts[1];

        final resolvedTable =
            context.resolveTable(tableOrAlias) ?? tableOrAlias;
        orderByColumns.add(QueryDependencyColumn(resolvedTable, columnName));
      } else if (baseTableName != null) {
        // Unqualified column - use base table
        orderByColumns.add(QueryDependencyColumn(baseTableName, columnExpr));
      }
    }

    dependencies = dependencies.merge(QueryDependencies(
      tables: <String>{},
      columns: orderByColumns,
      usesWildcard: false,
    ));

    // Add columns from GROUP BY clause
    final groupByColumns = <QueryDependencyColumn>{};
    for (final columnExpr in _groupBy) {
      if (columnExpr.contains('.')) {
        // Qualified column (table.column or alias.column)
        final parts = columnExpr.split('.');
        final tableOrAlias = parts[0];
        final columnName = parts[1];

        final resolvedTable =
            context.resolveTable(tableOrAlias) ?? tableOrAlias;
        groupByColumns.add(QueryDependencyColumn(resolvedTable, columnName));
      } else if (baseTableName != null) {
        // Unqualified column - use base table
        groupByColumns.add(QueryDependencyColumn(baseTableName, columnExpr));
      }
    }

    dependencies = dependencies.merge(QueryDependencies(
      tables: <String>{},
      columns: groupByColumns,
      usesWildcard: false,
    ));

    // Note: HAVING clause analysis would require WhereClause type
    // Currently _having is a String, so we can't analyze it structurally

    return dependencies;
  }
}
