import 'query_builder.dart';
import 'where_clause.dart';
import '../schema/db_view.dart';

class ViewBuilder {
  final String name;
  final List<String> _selectColumns = [];
  final List<String> _fromClauses = [];
  final List<String> _joinClauses = [];
  final List<WhereClause> _whereClauses = [];
  final List<String> _groupByColumns = [];
  final List<String> _havingClauses = [];
  final List<String> _orderByColumns = [];
  bool _hasFrom = false;

  ViewBuilder(this.name);

  /// Select a single column with optional alias
  /// Each column must be specified in a separate select() call
  ViewBuilder select(String columnExpression, [String? alias]) {
    assert(columnExpression.isNotEmpty, 
        'Column expression cannot be empty');
    assert(!columnExpression.contains(','), 
        'Multiple columns in single select() call are not allowed. '
        'Use separate select() calls for each column: '
        'view.select("col1").select("col2") instead of view.select("col1, col2")');
    assert(!columnExpression.toLowerCase().contains(' as ') || alias == null,
        'Do not use both inline AS alias and alias parameter. '
        'Use either select("column AS alias") or select("column", "alias")');
    
    if (alias != null) {
      _selectColumns.add('$columnExpression AS $alias');
    } else {
      _selectColumns.add(columnExpression);
    }
    return this;
  }

  ViewBuilder selectSubQuery(
      void Function(QueryBuilder) callback, String alias) {
    assert(alias.isNotEmpty, 'Sub-query alias cannot be empty');
    assert(!alias.contains(' '), 'Alias cannot contain spaces');
    
    final subQueryBuilder = QueryBuilder();
    callback(subQueryBuilder);
    final built = subQueryBuilder.build();
    final subQuery = built.$1;
    
    _selectColumns.add('($subQuery) AS $alias');
    return this;
  }

  ViewBuilder from(String table, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(!_hasFrom, 'FROM clause already specified. Use joins for additional tables.');
    assert(_fromClauses.isEmpty, 'FROM clause already specified');
    
    if (alias != null) {
      assert(alias.isNotEmpty, 'Table alias cannot be empty');
      assert(!alias.contains(' '), 'Table alias cannot contain spaces');
      _fromClauses.add('$table AS $alias');
    } else {
      _fromClauses.add(table);
    }
    _hasFrom = true;
    return this;
  }

  ViewBuilder fromSubQuery(
    void Function(QueryBuilder) build, [
    String? alias,
  ]) {
    assert(!_hasFrom, 'FROM clause already specified');
    assert(_fromClauses.isEmpty, 'FROM clause already specified');
    
    final subQueryBuilder = QueryBuilder();
    build(subQueryBuilder);
    final built = subQueryBuilder.build();
    final subQuery = built.$1;

    if (alias != null) {
      assert(alias.isNotEmpty, 'Sub-query alias cannot be empty');
      assert(!alias.contains(' '), 'Sub-query alias cannot contain spaces');
      _fromClauses.add('($subQuery) AS $alias');
    } else {
      _fromClauses.add('($subQuery)');
    }
    _hasFrom = true;
    return this;
  }

  @Deprecated('Use typed join methods instead: innerJoin(), leftJoin(), etc.')
  ViewBuilder join(String joinClause) {
    assert(joinClause.isNotEmpty, 'Join clause cannot be empty');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    _joinClauses.add(joinClause);
    return this;
  }

  /// Inner join with proper condition builder support
  ViewBuilder innerJoin(String table, WhereClause onCondition, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final built = onCondition.build();
    _joinClauses.add('INNER JOIN $tableWithAlias ON ${built.sql}');
    return this;
  }

  /// Left join with proper condition builder support  
  ViewBuilder leftJoin(String table, WhereClause onCondition, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final built = onCondition.build();
    _joinClauses.add('LEFT JOIN $tableWithAlias ON ${built.sql}');
    return this;
  }

  /// Right join with proper condition builder support
  ViewBuilder rightJoin(String table, WhereClause onCondition, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final built = onCondition.build();
    _joinClauses.add('RIGHT JOIN $tableWithAlias ON ${built.sql}');
    return this;
  }

  /// Full outer join with proper condition builder support
  ViewBuilder fullOuterJoin(String table, WhereClause onCondition, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final built = onCondition.build();
    _joinClauses.add('FULL OUTER JOIN $tableWithAlias ON ${built.sql}');
    return this;
  }

  /// Cross join (Cartesian product)
  ViewBuilder crossJoin(String table, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    _joinClauses.add('CROSS JOIN $tableWithAlias');
    return this;
  }

  ViewBuilder where(WhereClause condition) {
    assert(_hasFrom, 'FROM clause must be specified before WHERE clause');
    
    _whereClauses.add(condition);
    return this;
  }

  ViewBuilder groupBy(List<String> columns) {
    assert(columns.isNotEmpty, 'GROUP BY columns cannot be empty');
    assert(columns.every((col) => col.isNotEmpty), 'GROUP BY column names cannot be empty');
    assert(_hasFrom, 'FROM clause must be specified before GROUP BY clause');
    
    _groupByColumns.addAll(columns);
    return this;
  }

  @Deprecated('Use WhereClause builder for HAVING conditions')
  ViewBuilder having(String condition) {
    assert(condition.isNotEmpty, 'HAVING condition cannot be empty');
    assert(_groupByColumns.isNotEmpty, 'GROUP BY clause must be specified before HAVING clause');
    
    _havingClauses.add(condition);
    return this;
  }

  ViewBuilder orderBy(List<String> columns) {
    assert(columns.isNotEmpty, 'ORDER BY columns cannot be empty');
    assert(columns.every((col) => col.isNotEmpty), 'ORDER BY column names cannot be empty');
    assert(_hasFrom, 'FROM clause must be specified before ORDER BY clause');
    
    _orderByColumns.addAll(columns);
    return this;
  }

  DbView build() {
    assert(_selectColumns.isNotEmpty, 'At least one SELECT column must be specified');
    assert(_hasFrom, 'FROM clause must be specified');
    
    // Parse SELECT columns into ViewColumn objects
    final columns = _selectColumns.map((colExpr) {
      // Handle "expression AS alias" format
      if (colExpr.toUpperCase().contains(' AS ')) {
        final parts = colExpr.split(RegExp(r'\s+AS\s+', caseSensitive: false));
        if (parts.length == 2) {
          return ViewColumn(
            expression: parts[0].trim(),
            alias: parts[1].trim(),
          );
        }
      }
      
      // Simple column expression
      return ViewColumn(expression: colExpr.trim());
    }).toList();
    
    // Parse FROM tables into ViewTable objects
    final fromTables = _fromClauses.map((fromExpr) {
      // Handle "table AS alias" format
      if (fromExpr.toUpperCase().contains(' AS ')) {
        final parts = fromExpr.split(RegExp(r'\s+AS\s+', caseSensitive: false));
        if (parts.length == 2) {
          return ViewTable(
            name: parts[0].trim(),
            alias: parts[1].trim(),
          );
        }
      }
      
      // Simple table name
      return ViewTable(name: fromExpr.trim());
    }).toList();
    
    // Parse JOIN clauses into ViewJoin objects
    final joins = _joinClauses.map((joinExpr) {
      // Parse join expressions like "INNER JOIN table AS alias ON condition"
      final joinRegex = RegExp(r'^(\w+(?:\s+\w+)?)\s+JOIN\s+([^\s]+)(?:\s+AS\s+([^\s]+))?(?:\s+ON\s+(.+))?', caseSensitive: false);
      final match = joinRegex.firstMatch(joinExpr);
      
      if (match != null) {
        return ViewJoin(
          type: match.group(1)!.toUpperCase(),
          table: match.group(2)!,
          alias: match.group(3),
          onCondition: match.group(4),
        );
      }
      
      // Fallback for complex join expressions
      return ViewJoin(
        type: 'INNER',
        table: 'unknown',
        onCondition: joinExpr,
      );
    }).toList();
    
    // Convert WHERE clauses to strings
    final whereStrings = _whereClauses.map((whereClause) {
      final built = whereClause.build();
      return built.sql;
    }).toList();
    
    return DbView(
      name: name,
      columns: columns,
      fromTables: fromTables,
      joins: joins,
      whereClauses: whereStrings,
      groupByColumns: List.from(_groupByColumns),
      havingClauses: List.from(_havingClauses),
      orderByColumns: List.from(_orderByColumns),
    );
  }
}
