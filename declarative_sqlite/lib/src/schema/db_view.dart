/// Represents a database view with structured information about its components
class DbView {
  final String name;
  final List<ViewColumn> columns;
  final List<ViewTable> fromTables;
  final List<ViewJoin> joins;
  final List<String> whereClauses;
  final List<String> groupByColumns;
  final List<String> havingClauses;
  final List<String> orderByColumns;

  bool get isSystem => name.startsWith('__');

  const DbView({
    required this.name,
    required this.columns,
    required this.fromTables,
    this.joins = const [],
    this.whereClauses = const [],
    this.groupByColumns = const [],
    this.havingClauses = const [],
    this.orderByColumns = const [],
  });

  /// Generates the SQL definition for this view
  String get definition {
    final buffer = StringBuffer();
    
    // SELECT clause
    buffer.write('SELECT ${columns.map((c) => c.toSql()).join(', ')}');
    
    // FROM clause
    if (fromTables.isNotEmpty) {
      buffer.write(' FROM ${fromTables.map((t) => t.toSql()).join(', ')}');
    }
    
    // JOIN clauses
    if (joins.isNotEmpty) {
      buffer.write(' ${joins.map((j) => j.toSql()).join(' ')}');
    }
    
    // WHERE clause
    if (whereClauses.isNotEmpty) {
      buffer.write(' WHERE ${whereClauses.join(' AND ')}');
    }
    
    // GROUP BY clause
    if (groupByColumns.isNotEmpty) {
      buffer.write(' GROUP BY ${groupByColumns.join(', ')}');
    }
    
    // HAVING clause
    if (havingClauses.isNotEmpty) {
      buffer.write(' HAVING ${havingClauses.join(' AND ')}');
    }
    
    // ORDER BY clause
    if (orderByColumns.isNotEmpty) {
      buffer.write(' ORDER BY ${orderByColumns.join(', ')}');
    }
    
    return buffer.toString();
  }

  String toSql() {
    return 'CREATE VIEW $name AS $definition';
  }

  DbView copyWith({
    String? name,
    List<ViewColumn>? columns,
    List<ViewTable>? fromTables,
    List<ViewJoin>? joins,
    List<String>? whereClauses,
    List<String>? groupByColumns,
    List<String>? havingClauses,
    List<String>? orderByColumns,
  }) {
    return DbView(
      name: name ?? this.name,
      columns: columns ?? this.columns,
      fromTables: fromTables ?? this.fromTables,
      joins: joins ?? this.joins,
      whereClauses: whereClauses ?? this.whereClauses,
      groupByColumns: groupByColumns ?? this.groupByColumns,
      havingClauses: havingClauses ?? this.havingClauses,
      orderByColumns: orderByColumns ?? this.orderByColumns,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'columns': columns.map((c) => c.toMap()).toList(),
      'fromTables': fromTables.map((t) => t.toMap()).toList(),
      'joins': joins.map((j) => j.toMap()).toList(),
      'whereClauses': whereClauses,
      'groupByColumns': groupByColumns,
      'havingClauses': havingClauses,
      'orderByColumns': orderByColumns,
      'definition': definition,
    };
  }
}

/// Represents a column in a view's SELECT clause
class ViewColumn {
  final String expression;
  final String? alias;
  final String? sourceTable;
  final String? sourceColumn;

  const ViewColumn({
    required this.expression,
    this.alias,
    this.sourceTable,
    this.sourceColumn,
  });

  /// The effective name of this column (alias if provided, otherwise derived from expression)
  String get name {
    if (alias != null) return alias!;
    
    // Try to extract column name from simple expressions like "table.column"
    if (expression.contains('.')) {
      return expression.split('.').last;
    }
    
    return expression;
  }

  String toSql() {
    if (alias != null) {
      return '$expression AS $alias';
    }
    return expression;
  }

  Map<String, dynamic> toMap() {
    return {
      'expression': expression,
      'alias': alias,
      'sourceTable': sourceTable,
      'sourceColumn': sourceColumn,
    };
  }
}

/// Represents a table in the FROM clause
class ViewTable {
  final String name;
  final String? alias;

  const ViewTable({
    required this.name,
    this.alias,
  });

  String toSql() {
    if (alias != null) {
      return '$name AS $alias';
    }
    return name;
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'alias': alias,
    };
  }
}

/// Represents a JOIN clause in the view
class ViewJoin {
  final String type; // INNER, LEFT, RIGHT, FULL OUTER, CROSS
  final String table;
  final String? alias;
  final String? onCondition;

  const ViewJoin({
    required this.type,
    required this.table,
    this.alias,
    this.onCondition,
  });

  String toSql() {
    final buffer = StringBuffer();
    buffer.write('$type JOIN ');
    
    if (alias != null) {
      buffer.write('$table AS $alias');
    } else {
      buffer.write(table);
    }
    
    if (onCondition != null) {
      buffer.write(' ON $onCondition');
    }
    
    return buffer.toString();
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'table': table,
      'alias': alias,
      'onCondition': onCondition,
    };
  }
}
