import '../builders/analysis_context.dart';
import '../builders/query_builder.dart';
import '../builders/query_dependencies.dart';
import '../builders/where_clause.dart';

/// Analyzes queries to determine their database dependencies using object-oriented approach.
/// 
/// This analyzer uses the self-reporting pattern where QueryBuilder and WhereClause
/// objects analyze their own dependencies rather than external SQL parsing.
/// Requires a schema provider to accurately resolve unqualified column references.
/// 
/// For complex queries with subqueries, joins, or intricate WHERE clauses, the analyzer
/// may fall back to table-level dependencies to ensure reliability. This conservative
/// approach prevents missed updates when column-level analysis might be incomplete.
class QueryDependencyAnalyzer {
  final SchemaProvider _schema;

  /// Creates a query dependency analyzer with the required schema provider.
  /// 
  /// The schema enables accurate resolution of unqualified column references
  /// to their correct tables, which is essential for proper dependency tracking
  /// in complex queries with multiple tables and subqueries.
  QueryDependencyAnalyzer(this._schema);

  /// Creates a schema-aware analysis context for use in custom analysis.
  AnalysisContext createAnalysisContext() {
    return AnalysisContext(_schema);
  }
  /// Analyzes a QueryBuilder to extract all database dependencies.
  ///
  /// Returns a [QueryDependencies] object containing:
  /// - Tables referenced in the query
  /// - Columns referenced in the query  
  /// - Whether wildcard selection (*) is used
  ///
  /// Uses schema information to accurately resolve unqualified column references
  /// to their correct tables. For complex queries where column-level analysis
  /// might miss dependencies, the system falls back to table-level tracking
  /// to ensure streaming queries update reliably when underlying data changes.
  QueryDependencies analyzeQuery(QueryBuilder builder) {
    final context = AnalysisContext(_schema);
    return builder.analyzeDependencies(context);
  }

  /// Analyzes a WHERE clause to extract column and table dependencies.
  ///
  /// Useful for analyzing WHERE clauses in isolation, such as for 
  /// conditional updates or filtered queries.
  /// Uses schema information for accurate column-to-table resolution.
  QueryDependencies analyzeWhereClause(WhereClause whereClause, [AnalysisContext? context]) {
    final analysisContext = context ?? AnalysisContext(_schema);
    return whereClause.analyzeDependencies(analysisContext);
  }

  /// Checks if a query depends on a specific table.
  ///
  /// This is useful for cache invalidation - if a table is modified,
  /// all queries that depend on it should have their cached results invalidated.
  bool queryDependsOnTable(QueryBuilder builder, String tableName) {
    final dependencies = analyzeQuery(builder);
    return dependencies.tables.contains(tableName) ||
           dependencies.tables.any((table) => table.split(' ').first == tableName);
  }

  /// Checks if a query depends on a specific column.
  ///
  /// This provides fine-grained dependency tracking for optimized caching.
  bool queryDependsOnColumn(QueryBuilder builder, String columnName) {
    final dependencies = analyzeQuery(builder);
    
    // Check for column match by name
    return dependencies.columns.any((col) => col.column == columnName);
  }

  /// Gets all tables that a query depends on.
  ///
  /// Returns table names without aliases for consistent cache key generation.
  Set<String> getQueryTables(QueryBuilder builder) {
    final dependencies = analyzeQuery(builder);
    
    // Extract base table names (remove aliases)
    return dependencies.tables.map((table) {
      final parts = table.split(' ');
      return parts.first; // Get table name before any AS alias
    }).toSet();
  }

  /// Gets all columns that a query depends on.
  ///
  /// Returns QueryDependencyColumn objects with table and column information.
  Set<QueryDependencyColumn> getQueryColumns(QueryBuilder builder) {
    final dependencies = analyzeQuery(builder);
    return Set.from(dependencies.columns);
  }

  /// Checks if a query uses wildcard selection.
  ///
  /// Wildcard queries depend on all columns of their referenced tables
  /// and require broader cache invalidation strategies.
  bool usesWildcardSelection(QueryBuilder builder) {
    final dependencies = analyzeQuery(builder);
    return dependencies.usesWildcard;
  }
}