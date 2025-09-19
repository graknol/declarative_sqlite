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
class QueryDependencyAnalyzer {
  final Schema _schema;
  
  QueryDependencyAnalyzer(this._schema);

  /// Analyzes a QueryBuilder to extract its dependencies using schema metadata
  QueryDependencies analyze(QueryBuilder builder) {
    final dependencies = <String>{};
    final columns = <String>{};
    bool usesWildcard = false;

    // Collect dependencies recursively from the query builder
    _collectQueryBuilderDependencies(builder, dependencies, columns);
    
    // Check if wildcard is used by examining the query structure
    usesWildcard = _detectWildcardUsage(builder);

    return QueryDependencies(
      tables: dependencies,
      columns: columns,
      usesWildcard: usesWildcard,
    );
  }

  /// Recursively collects dependencies from a QueryBuilder using reflection on its structure
  void _collectQueryBuilderDependencies(
    QueryBuilder builder, 
    Set<String> dependencies, 
    Set<String> columns
  ) {
    // Get the SQL to parse the builder's state
    // Note: This is a transitional approach - we should ideally expose
    // the builder's internal state directly for better analysis
    final (sql, _) = builder.build();
    
    // Extract dependencies using schema-aware parsing
    _extractDependenciesFromSQL(sql, dependencies, columns);
    
    // For each dependency found, recursively analyze if it's a view
    final currentDeps = Set<String>.from(dependencies);
    for (final tableName in currentDeps) {
      _collectViewDependencies(tableName, dependencies, columns);
    }
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

  /// Detects wildcard usage in the query
  bool _detectWildcardUsage(QueryBuilder builder) {
    final (sql, _) = builder.build();
    return sql.toLowerCase().contains('select *');
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