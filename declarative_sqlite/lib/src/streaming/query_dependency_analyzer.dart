import '../builders/query_builder.dart';

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

/// Analyzes queries to determine their dependencies on database entities
class QueryDependencyAnalyzer {
  /// Analyzes a QueryBuilder to extract its dependencies
  static QueryDependencies analyze(QueryBuilder builder) {
    final (sql, _) = builder.build();
    return analyzeSQL(sql);
  }

  /// Analyzes raw SQL to extract dependencies
  static QueryDependencies analyzeSQL(String sql) {
    final tables = <String>{};
    final columns = <String>{};
    bool usesWildcard = false;

    try {
      // Normalize SQL for parsing (convert to lowercase, remove extra whitespace)
      final normalizedSQL = sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

      // Extract tables from FROM clauses
      final fromMatches = RegExp(r'from\s+(\w+)(?:\s+as\s+\w+)?').allMatches(normalizedSQL);
      for (final match in fromMatches) {
        final tableName = match.group(1)!;
        if (tableName.isNotEmpty && !_isSQLKeyword(tableName)) {
          tables.add(tableName);
        }
      }

      // Extract tables from JOIN clauses
      final joinMatches = RegExp(r'(?:inner\s+|left\s+|right\s+|cross\s+)?join\s+(\w+)(?:\s+as\s+\w+)?').allMatches(normalizedSQL);
      for (final match in joinMatches) {
        final tableName = match.group(1)!;
        if (tableName.isNotEmpty && !_isSQLKeyword(tableName)) {
          tables.add(tableName);
        }
      }

      // Check for wildcard select
      if (normalizedSQL.contains('select *')) {
        usesWildcard = true;
      } else {
        // Extract specific columns from SELECT clause
        final selectMatch = RegExp(r'select\s+(.*?)\s+from').firstMatch(normalizedSQL);
        if (selectMatch != null) {
          final selectClause = selectMatch.group(1)!;
          final columnMatches = RegExp(r'(\w+)\.(\w+)').allMatches(selectClause);
          for (final match in columnMatches) {
            final table = match.group(1)!;
            final column = match.group(2)!;
            if (!_isSQLKeyword(table) && !_isSQLKeyword(column)) {
              tables.add(table);
              columns.add('$table.$column');
            }
          }

          // Also extract unqualified column names and assume they belong to the main table
          final unqualifiedMatches = RegExp(r'\b(\w+)(?!\s*\()').allMatches(selectClause);
          final mainTable = tables.isNotEmpty ? tables.first : '';
          for (final match in unqualifiedMatches) {
            final column = match.group(1)!;
            // Skip SQL keywords, function names, and aliases
            if (!_isSQLKeyword(column) && mainTable.isNotEmpty && !column.contains('.')) {
              columns.add('$mainTable.$column');
            }
          }
        }
      }

      // Extract tables and columns from WHERE clauses
      final whereMatch = RegExp(r'where\s+(.*?)(?:\s+(?:group\s+by|order\s+by|limit)|$)').firstMatch(normalizedSQL);
      if (whereMatch != null) {
        final whereClause = whereMatch.group(1)!;
        final whereColumnMatches = RegExp(r'(\w+)\.(\w+)').allMatches(whereClause);
        for (final match in whereColumnMatches) {
          final table = match.group(1)!;
          final column = match.group(2)!;
          if (!_isSQLKeyword(table) && !_isSQLKeyword(column)) {
            tables.add(table);
            columns.add('$table.$column');
          }
        }
      }
    } catch (e) {
      // If parsing fails, return safe defaults
      // This ensures the system continues to work even with complex/malformed SQL
    }

    return QueryDependencies(
      tables: tables,
      columns: columns,
      usesWildcard: usesWildcard,
    );
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
}