import 'analysis_context.dart';
import 'query_dependencies.dart';

/// Represents a column reference in a SQL query
/// 
/// Can be a simple column, qualified column, aggregate function, or complex expression.
/// Handles parsing at construction time and provides structured dependency analysis.
abstract class QueryColumn {
  /// The original expression as provided by the user
  final String expression;
  
  const QueryColumn(this.expression);
  
  /// Factory constructor that parses column expressions and returns appropriate Column subtype
  factory QueryColumn.parse(String expression) {
    // Trim whitespace
    final trimmed = expression.trim();
    
    // Check for wildcard
    if (trimmed == '*' || trimmed.endsWith('.*')) {
      return WildcardColumn(trimmed);
    }
    
    // Check for aggregate functions (simple heuristic)
    final upperExpression = trimmed.toUpperCase();
    if (RegExp(r'^(COUNT|SUM|AVG|MIN|MAX|GROUP_CONCAT)\s*\(').hasMatch(upperExpression)) {
      return AggregateColumn(trimmed);
    }
    
    // Check for ORDER BY expressions with ASC/DESC (extract the column part)
    final orderByMatch = RegExp(r'^(.+?)\s+(ASC|DESC)$', caseSensitive: false).firstMatch(trimmed);
    if (orderByMatch != null) {
      final columnPart = orderByMatch.group(1)!.trim();
      return QueryColumn.parse(columnPart); // Recursively parse the column part
    }
    
    // Check for complex expressions (contains operators, functions, literals)
    if (RegExp(r'[+\-*/()]|CASE\s|WHEN\s|THEN\s|ELSE\s|END\s').hasMatch(upperExpression)) {
      return ExpressionColumn(trimmed);
    }
    
    // Check for qualified column (table.column or alias.column)
    if (trimmed.contains('.') && !trimmed.startsWith('.') && !trimmed.endsWith('.')) {
      final parts = trimmed.split('.');
      if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        return QualifiedColumn(trimmed, parts[0], parts[1]);
      }
    }
    
    // Simple column name
    return SimpleColumn(trimmed);
  }
  
  /// Analyzes this column's dependencies
  QueryDependencies analyzeDependencies(AnalysisContext context, [String? fallbackTable]);
  
  /// Renders the column as SQL
  String toSql();
  
  @override
  String toString() => toSql();
}

/// A simple column name without table qualification
class SimpleColumn extends QueryColumn {
  final String columnName;
  
  const SimpleColumn(super.expression) : 
    columnName = expression;
  
  @override
  QueryDependencies analyzeDependencies(AnalysisContext context, [String? fallbackTable]) {
    // Try to resolve the column to an appropriate table
    final resolvedTable = fallbackTable ?? context.resolveUnqualifiedColumn(columnName);
    
    if (resolvedTable != null) {
      return QueryDependencies(
        tables: <String>{},
        columns: {QueryDependencyColumn(resolvedTable, columnName)},
        usesWildcard: false,
      );
    }
    
    // If we can't resolve the table, return empty dependencies
    // This shouldn't happen in well-formed queries
    return QueryDependencies.empty();
  }
  
  @override
  String toSql() => columnName;
}

/// A qualified column with table/alias prefix (e.g., "u.name", "posts.title")
class QualifiedColumn extends QueryColumn {
  final String tableOrAlias;
  final String columnName;
  
  const QualifiedColumn(super.expression, this.tableOrAlias, this.columnName);
  
  @override
  QueryDependencies analyzeDependencies(AnalysisContext context, [String? fallbackTable]) {
    final resolvedTable = context.resolveTable(tableOrAlias) ?? tableOrAlias;
    return QueryDependencies(
      tables: <String>{},
      columns: {QueryDependencyColumn(resolvedTable, columnName)},
      usesWildcard: false,
    );
  }
  
  @override
  String toSql() => '$tableOrAlias.$columnName';
}

/// A wildcard column (* or table.*)
class WildcardColumn extends QueryColumn {
  final String? tableOrAlias;
  
  WildcardColumn(super.expression) : 
    tableOrAlias = expression.contains('.') ? expression.split('.')[0] : null;
  
  @override
  QueryDependencies analyzeDependencies(AnalysisContext context, [String? fallbackTable]) {
    return QueryDependencies(
      tables: <String>{},
      columns: <QueryDependencyColumn>{},
      usesWildcard: true,
    );
  }
  
  @override
  String toSql() => expression;
}

/// An aggregate function column (e.g., "COUNT(*)", "SUM(amount)")
class AggregateColumn extends QueryColumn {
  const AggregateColumn(super.expression);
  
  @override
  QueryDependencies analyzeDependencies(AnalysisContext context, [String? fallbackTable]) {
    var dependencies = QueryDependencies.empty();
    
    // Extract column references from within the aggregate function
    // This is a simple approach - we could make it more sophisticated
    final columnRefs = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*\.)?([a-zA-Z_][a-zA-Z0-9_]*)')
        .allMatches(expression);
    
    for (final match in columnRefs) {
      final tableOrAlias = match.group(1)?.replaceAll('.', '');
      final columnName = match.group(2)!;
      
      // Skip SQL keywords and function names
      final upperColumn = columnName.toUpperCase();
      if (['COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'GROUP_CONCAT', 'DISTINCT'].contains(upperColumn)) {
        continue;
      }
      
      if (tableOrAlias != null) {
        final resolvedTable = context.resolveTable(tableOrAlias) ?? tableOrAlias;
        dependencies = dependencies.merge(QueryDependencies(
          tables: <String>{},
          columns: {QueryDependencyColumn(resolvedTable, columnName)},
          usesWildcard: false,
        ));
      } else if (fallbackTable != null) {
        dependencies = dependencies.merge(QueryDependencies(
          tables: <String>{},
          columns: {QueryDependencyColumn(fallbackTable, columnName)},
          usesWildcard: false,
        ));
      }
    }
    
    return dependencies;
  }
  
  @override
  String toSql() => expression;
}

/// A complex expression column (e.g., calculations, CASE statements)
class ExpressionColumn extends QueryColumn {
  const ExpressionColumn(super.expression);
  
  @override
  QueryDependencies analyzeDependencies(AnalysisContext context, [String? fallbackTable]) {
    var dependencies = QueryDependencies.empty();
    
    // Extract column references from the expression
    // This is a simple regex approach - could be made more sophisticated with proper SQL parsing
    final columnRefs = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*\.)?([a-zA-Z_][a-zA-Z0-9_]*)')
        .allMatches(expression);
    
    for (final match in columnRefs) {
      final tableOrAlias = match.group(1)?.replaceAll('.', '');
      final columnName = match.group(2)!;
      
      // Skip SQL keywords and function names
      final upperColumn = columnName.toUpperCase();
      if (['CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'AND', 'OR', 'NOT', 'NULL', 'TRUE', 'FALSE'].contains(upperColumn)) {
        continue;
      }
      
      if (tableOrAlias != null) {
        final resolvedTable = context.resolveTable(tableOrAlias) ?? tableOrAlias;
        dependencies = dependencies.merge(QueryDependencies(
          tables: <String>{},
          columns: {QueryDependencyColumn(resolvedTable, columnName)},
          usesWildcard: false,
        ));
      } else if (fallbackTable != null) {
        dependencies = dependencies.merge(QueryDependencies(
          tables: <String>{},
          columns: {QueryDependencyColumn(fallbackTable, columnName)},
          usesWildcard: false,
        ));
      }
    }
    
    return dependencies;
  }
  
  @override
  String toSql() => expression;
}