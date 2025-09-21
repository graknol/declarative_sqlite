import 'query_builder.dart';
import 'where_clause.dart';
import '../schema/view.dart';

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
    assert(callback != null, 'Sub-query callback cannot be null');
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
    assert(build != null, 'Sub-query builder callback cannot be null');
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
    assert(onCondition != null, 'Join condition cannot be null. Use WhereClause builder: col("table1.id").eq(col("table2.id"))');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final built = onCondition.build();
    _joinClauses.add('INNER JOIN $tableWithAlias ON ${built.sql}');
    return this;
  }

  /// Left join with proper condition builder support  
  ViewBuilder leftJoin(String table, WhereClause onCondition, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(onCondition != null, 'Join condition cannot be null. Use WhereClause builder: col("table1.id").eq(col("table2.id"))');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final built = onCondition.build();
    _joinClauses.add('LEFT JOIN $tableWithAlias ON ${built.sql}');
    return this;
  }

  /// Right join with proper condition builder support
  ViewBuilder rightJoin(String table, WhereClause onCondition, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(onCondition != null, 'Join condition cannot be null. Use WhereClause builder: col("table1.id").eq(col("table2.id"))');
    assert(_hasFrom, 'FROM clause must be specified before joins');
    
    final tableWithAlias = alias != null ? '$table AS $alias' : table;
    final built = onCondition.build();
    _joinClauses.add('RIGHT JOIN $tableWithAlias ON ${built.sql}');
    return this;
  }

  /// Full outer join with proper condition builder support
  ViewBuilder fullOuterJoin(String table, WhereClause onCondition, [String? alias]) {
    assert(table.isNotEmpty, 'Table name cannot be empty');
    assert(onCondition != null, 'Join condition cannot be null. Use WhereClause builder: col("table1.id").eq(col("table2.id"))');
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
    assert(condition != null, 'WHERE condition cannot be null. Use WhereClause builder: col("column").eq("value")');
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

  View build() {
    assert(_selectColumns.isNotEmpty, 'At least one SELECT column must be specified');
    assert(_hasFrom, 'FROM clause must be specified');
    
    final definition = StringBuffer();
    
    // SELECT clause
    definition.write('SELECT ${_selectColumns.join(', ')}');
    
    // FROM clause
    definition.write(' FROM ${_fromClauses.join(', ')}');
    
    // JOIN clauses
    if (_joinClauses.isNotEmpty) {
      definition.write(' ${_joinClauses.join(' ')}');
    }
    
    // WHERE clause
    if (_whereClauses.isNotEmpty) {
      final combinedWhere = and(_whereClauses);
      final built = combinedWhere.build();
      definition.write(' WHERE ${built.sql}');
    }
    
    // GROUP BY clause
    if (_groupByColumns.isNotEmpty) {
      definition.write(' GROUP BY ${_groupByColumns.join(', ')}');
    }
    
    // HAVING clause
    if (_havingClauses.isNotEmpty) {
      definition.write(' HAVING ${_havingClauses.join(' AND ')}');
    }
    
    // ORDER BY clause
    if (_orderByColumns.isNotEmpty) {
      definition.write(' ORDER BY ${_orderByColumns.join(', ')}');
    }
    
    return View(name: name, definition: definition.toString());
  }
}
