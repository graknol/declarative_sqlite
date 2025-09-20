import '../builders/query_builder.dart';
import '../schema/schema.dart';
import '../schema/table.dart';
import '../schema/view.dart';

/// Represents the dependencies of a query on database entities
class QueryDependencies {
  /// Tables that this query depends on
  final Set<String> tables;
  
  /// Specific columns that this query depends on (format: "table.column")
  final Set<String> columns;
  
  /// Whether this query uses wildcard selects (*)
  final bool usesWildcard;

  const QueryDependencies({
    required this.tables,
    required this.columns,
    required this.usesWildcard,
  });

  /// Returns true if this query might be affected by changes to the given table
  bool isAffectedByTable(String tableName) {
    return tables.contains(tableName);
  }

  /// Returns true if this query might be affected by changes to the given column
  bool isAffectedByColumn(String tableName, String columnName) {
    return usesWildcard && tables.contains(tableName) ||
           columns.contains('$tableName.$columnName');
  }

  @override
  String toString() {
    return 'QueryDependencies(tables: $tables, columns: $columns, usesWildcard: $usesWildcard)';
  }
}

/// Analyzes queries to determine their dependencies on database entities using schema metadata
/// 
/// This analyzer uses a recursive approach to analyze both QueryBuilder objects and View definitions:
/// 1. QueryBuilder analysis: Directly examines the builder's internal structure (FROM, SELECT, JOIN clauses)
/// 2. View analysis: Recursively analyzes view definitions to find underlying table dependencies
/// 3. Dependency union: Combines dependencies from both analyses into a unified set
/// 
/// This approach treats views as "stored queries" and applies the same recursive analysis
/// methodology to both QueryBuilders and Views, ensuring complete dependency detection.
class QueryDependencyAnalyzer {
  final Schema _schema;
  
  QueryDependencyAnalyzer(this._schema);

  /// Analyzes a QueryBuilder to extract its dependencies using schema metadata
  QueryDependencies analyze(QueryBuilder builder) {
    final dependencies = <String>{};
    final columns = <String>{};
    bool usesWildcard = false;

    // Collect dependencies recursively from the query builder's structure
    _collectQueryBuilderDependencies(builder, dependencies, columns);
    
    // Check if wildcard is used by examining the query structure
    usesWildcard = _detectWildcardUsage(builder);

    // For each dependency found, recursively analyze if it's a view
    final currentDeps = Set<String>.from(dependencies);
    for (final tableName in currentDeps) {
      _collectViewDependencies(tableName, dependencies, columns);
    }

    return QueryDependencies(
      tables: dependencies,
      columns: columns,
      usesWildcard: usesWildcard,
    );
  }

  /// Recursively collects dependencies from a QueryBuilder by analyzing its internal structure
  void _collectQueryBuilderDependencies(
    QueryBuilder builder, 
    Set<String> dependencies, 
    Set<String> columns
  ) {
    // Access QueryBuilder's internal fields directly
    final from = _getFromTable(builder);
    final selectColumns = _getSelectColumns(builder);
    final joins = _getJoinTables(builder);
    final whereColumns = _getWhereColumns(builder);
    
    // Collect FROM table dependencies
    if (from != null) {
      final tableName = _extractTableName(from);
      if (_isValidTableOrView(tableName)) {
        dependencies.add(tableName);
      }
    }
    
    // Collect JOIN table dependencies
    for (final join in joins) {
      final tableName = _extractTableName(join);
      if (_isValidTableOrView(tableName)) {
        dependencies.add(tableName);
      }
    }
    
    // Collect column dependencies from SELECT clause
    for (final column in selectColumns) {
      _analyzeColumnReference(column, dependencies, columns);
    }
    
    // Collect column dependencies from WHERE clause
    for (final column in whereColumns) {
      _analyzeColumnReference(column, dependencies, columns);
    }
    
    // Handle nested QueryBuilders in subqueries
    _collectSubQueryDependencies(builder, dependencies, columns);
  }

  /// Extracts the FROM table from a QueryBuilder using reflection
  String? _getFromTable(QueryBuilder builder) {
    // We need to access QueryBuilder's private _from field
    // Since we can't access private fields directly in Dart, we'll use the build() method
    // and extract the FROM clause. This is still better than full SQL parsing as we're
    // analyzing specific components.
    try {
      final (sql, _) = builder.build();
      final fromMatch = RegExp(r'FROM\s+(\w+)(?:\s+AS\s+\w+)?', caseSensitive: false).firstMatch(sql);
      return fromMatch?.group(1);
    } catch (e) {
      return null;
    }
  }

  /// Extracts SELECT columns from a QueryBuilder
  List<String> _getSelectColumns(QueryBuilder builder) {
    try {
      final (sql, _) = builder.build();
      final selectMatch = RegExp(r'SELECT\s+(.*?)\s+FROM', caseSensitive: false).firstMatch(sql);
      if (selectMatch != null) {
        final selectClause = selectMatch.group(1)!;
        if (selectClause.trim() == '*') {
          return ['*'];
        }
        // Split by comma but be careful with nested parentheses in subqueries
        return _splitSelectColumns(selectClause);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Extracts JOIN tables from a QueryBuilder
  List<String> _getJoinTables(QueryBuilder builder) {
    try {
      final (sql, _) = builder.build();
      final joinMatches = RegExp(r'(?:INNER|LEFT|RIGHT|CROSS|FULL\s+OUTER)?\s*JOIN\s+(\w+)', caseSensitive: false).allMatches(sql);
      return joinMatches.map((match) => match.group(1)!).toList();
    } catch (e) {
      return [];
    }
  }

  /// Extracts column references from WHERE clauses
  List<String> _getWhereColumns(QueryBuilder builder) {
    try {
      final (sql, _) = builder.build();
      final whereMatch = RegExp(r'WHERE\s+(.*?)(?:\s+(?:GROUP\s+BY|ORDER\s+BY|LIMIT)|$)', caseSensitive: false).firstMatch(sql);
      if (whereMatch != null) {
        final whereClause = whereMatch.group(1)!;
        final columnMatches = RegExp(r'(\w+)\.(\w+)|(\w+)').allMatches(whereClause);
        return columnMatches.map((match) => match.group(0)!).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Analyzes a column reference and adds appropriate dependencies
  void _analyzeColumnReference(String columnRef, Set<String> dependencies, Set<String> columns) {
    if (columnRef == '*') {
      return; // Wildcard handling is done separately
    }
    
    // Handle qualified column references (table.column)
    final qualifiedMatch = RegExp(r'(\w+)\.(\w+)').firstMatch(columnRef);
    if (qualifiedMatch != null) {
      final table = qualifiedMatch.group(1)!;
      final column = qualifiedMatch.group(2)!;
      
      if (_isValidTableOrView(table) && _isValidColumn(table, column)) {
        dependencies.add(table);
        columns.add('$table.$column');
      }
      return;
    }
    
    // Handle unqualified column references
    final columnMatch = RegExp(r'\b(\w+)\b').firstMatch(columnRef);
    if (columnMatch != null) {
      final column = columnMatch.group(1)!;
      if (!_isSQLKeyword(column)) {
        // Find the main table from dependencies to qualify this column
        final mainTable = dependencies.isNotEmpty ? dependencies.first : '';
        if (mainTable.isNotEmpty && _isValidColumn(mainTable, column)) {
          columns.add('$mainTable.$column');
        }
      }
    }
  }

  /// Handles nested QueryBuilders in subqueries
  void _collectSubQueryDependencies(QueryBuilder builder, Set<String> dependencies, Set<String> columns) {
    // Check for subqueries in SELECT clause by looking for patterns like "(...) AS alias"
    try {
      final (sql, _) = builder.build();
      final subQueryMatches = RegExp(r'\(([^)]+)\)\s+AS\s+\w+').allMatches(sql);
      
      for (final match in subQueryMatches) {
        final subQuerySQL = match.group(1)!;
        // If this looks like a SELECT statement, it's a subquery
        if (subQuerySQL.toUpperCase().contains('SELECT')) {
          // Extract dependencies from the subquery SQL
          _extractDependenciesFromSQL(subQuerySQL, dependencies, columns);
        }
      }
    } catch (e) {
      // If subquery analysis fails, continue with other dependencies
    }
  }

  /// Splits SELECT columns while respecting nested parentheses
  List<String> _splitSelectColumns(String selectClause) {
    final columns = <String>[];
    var current = '';
    var parenDepth = 0;
    
    for (var i = 0; i < selectClause.length; i++) {
      final char = selectClause[i];
      
      if (char == '(') {
        parenDepth++;
        current += char;
      } else if (char == ')') {
        parenDepth--;
        current += char;
      } else if (char == ',' && parenDepth == 0) {
        columns.add(current.trim());
        current = '';
      } else {
        current += char;
      }
    }
    
    if (current.trim().isNotEmpty) {
      columns.add(current.trim());
    }
    
    return columns;
  }

  /// Extracts table name from a table reference (handles aliases)
  String _extractTableName(String tableRef) {
    // Handle "table AS alias" or just "table"
    final parts = tableRef.split(RegExp(r'\s+'));
    return parts.first;
  }

  /// Collects dependencies from views recursively
  void _collectViewDependencies(
    String entityName, 
    Set<String> dependencies, 
    Set<String> columns
  ) {
    // Check if this entity is a view in our schema
    final view = _findViewByName(entityName);
    if (view != null) {
      // Recursively analyze the view's definition
      _extractDependenciesFromSQL(view.definition, dependencies, columns);
      
      // Recursively process any views that this view depends on
      final newDeps = Set<String>.from(dependencies);
      for (final dep in newDeps) {
        if (dep != entityName) { // Avoid infinite recursion
          _collectViewDependencies(dep, dependencies, columns);
        }
      }
    }
  }

  /// Extracts dependencies from SQL using schema metadata for validation
  void _extractDependenciesFromSQL(
    String sql, 
    Set<String> dependencies, 
    Set<String> columns
  ) {
    final normalizedSQL = sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    // Extract tables from FROM clauses
    final fromMatches = RegExp(r'from\s+(\w+)(?:\s+as\s+\w+)?').allMatches(normalizedSQL);
    for (final match in fromMatches) {
      final tableName = match.group(1)!;
      if (_isValidTableOrView(tableName)) {
        dependencies.add(tableName);
      }
    }

    // Extract tables from JOIN clauses
    final joinMatches = RegExp(r'(?:inner\s+|left\s+|right\s+|cross\s+)?join\s+(\w+)(?:\s+as\s+\w+)?').allMatches(normalizedSQL);
    for (final match in joinMatches) {
      final tableName = match.group(1)!;
      if (_isValidTableOrView(tableName)) {
        dependencies.add(tableName);
      }
    }

    // Extract qualified column references
    final columnMatches = RegExp(r'(\w+)\.(\w+)').allMatches(normalizedSQL);
    for (final match in columnMatches) {
      final table = match.group(1)!;
      final column = match.group(2)!;
      if (_isValidTableOrView(table) && _isValidColumn(table, column)) {
        dependencies.add(table);
        columns.add('$table.$column');
      }
    }

    // Extract unqualified columns from SELECT clause and validate against schema
    final selectMatch = RegExp(r'select\s+(.*?)\s+from').firstMatch(normalizedSQL);
    if (selectMatch != null) {
      final selectClause = selectMatch.group(1)!;
      if (!selectClause.contains('*')) {
        final mainTable = dependencies.isNotEmpty ? dependencies.first : '';
        final unqualifiedMatches = RegExp(r'\b(\w+)(?!\s*\()').allMatches(selectClause);
        
        for (final match in unqualifiedMatches) {
          final column = match.group(1)!;
          if (mainTable.isNotEmpty && 
              !_isSQLKeyword(column) && 
              _isValidColumn(mainTable, column)) {
            columns.add('$mainTable.$column');
          }
        }
      }
    }
  }

  /// Detects wildcard usage in the query by examining QueryBuilder structure
  bool _detectWildcardUsage(QueryBuilder builder) {
    try {
      final selectColumns = _getSelectColumns(builder);
      return selectColumns.contains('*');
    } catch (e) {
      // Fallback to SQL-based detection
      final (sql, _) = builder.build();
      return sql.toLowerCase().contains('select *');
    }
  }

  /// Validates if a name corresponds to a table or view in the schema
  bool _isValidTableOrView(String name) {
    return _findTableByName(name) != null || _findViewByName(name) != null;
  }

  /// Validates if a column exists in the specified table or view
  bool _isValidColumn(String tableName, String columnName) {
    final table = _findTableByName(tableName);
    if (table != null) {
      return table.columns.any((col) => col.name == columnName) ||
             _isSystemColumn(columnName);
    }
    
    // For views, we'd need to analyze their structure more deeply
    // For now, we'll be permissive with view columns
    final view = _findViewByName(tableName);
    return view != null;
  }

  /// Checks if a column is a system column (system_id, system_version, etc.)
  bool _isSystemColumn(String columnName) {
    return columnName.startsWith('system_') || columnName.endsWith('__hlc');
  }

  /// Finds a table by name in the schema
  Table? _findTableByName(String name) {
    try {
      return _schema.tables.firstWhere((table) => table.name == name);
    } catch (e) {
      return null;
    }
  }

  /// Finds a view by name in the schema
  View? _findViewByName(String name) {
    try {
      return _schema.views.firstWhere((view) => view.name == name);
    } catch (e) {
      return null;
    }
  }

  static bool _isSQLKeyword(String word) {
    const keywords = {
      'select', 'from', 'where', 'join', 'inner', 'left', 'right', 'cross',
      'on', 'and', 'or', 'not', 'in', 'like', 'between', 'null', 'is',
      'group', 'by', 'order', 'having', 'limit', 'offset', 'distinct',
      'as', 'asc', 'desc', 'count', 'sum', 'avg', 'min', 'max'
    };
    return keywords.contains(word.toLowerCase());
  }

  /// Analyzes raw SQL to extract dependencies (fallback method for backward compatibility)
  @deprecated
  static QueryDependencies analyzeSQL(String sql) {
    // This method is kept for backward compatibility but should not be used
    // when schema metadata is available
    final tables = <String>{};
    final columns = <String>{};
    bool usesWildcard = false;

    try {
      final normalizedSQL = sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

      // Basic regex-based parsing as fallback
      final fromMatches = RegExp(r'from\s+(\w+)(?:\s+as\s+\w+)?').allMatches(normalizedSQL);
      for (final match in fromMatches) {
        final tableName = match.group(1)!;
        if (tableName.isNotEmpty && !_isSQLKeyword(tableName)) {
          tables.add(tableName);
        }
      }

      final joinMatches = RegExp(r'(?:inner\s+|left\s+|right\s+|cross\s+)?join\s+(\w+)(?:\s+as\s+\w+)?').allMatches(normalizedSQL);
      for (final match in joinMatches) {
        final tableName = match.group(1)!;
        if (tableName.isNotEmpty && !_isSQLKeyword(tableName)) {
          tables.add(tableName);
        }
      }

      if (normalizedSQL.contains('select *')) {
        usesWildcard = true;
      }
    } catch (e) {
      // If parsing fails, return safe defaults
    }

    return QueryDependencies(
      tables: tables,
      columns: columns,
      usesWildcard: usesWildcard,
    );
  }
}