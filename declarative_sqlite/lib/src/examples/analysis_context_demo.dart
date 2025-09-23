import '../builders/query_builder.dart';
import '../builders/where_clause.dart';

/// Example demonstrating the AnalysisContext-based dependency analysis
void demonstrateAnalysisContext() {
  print('=== QueryDependencyColumn and AnalysisContext Demo ===\n');

  // Create a query with table alias
  final query = QueryBuilder()
    ..from('users', 'u')  // users table with alias 'u'
    ..select('u.id')      // qualified with alias
    ..select('name')      // unqualified - should resolve to 'users.name'
    ..select('email')     // unqualified - should resolve to 'users.email'
    ..where(
      and([
        col('u.active').eq(true),           // qualified with alias
        col('created_at').gt('2023-01-01'), // unqualified - should resolve to users.created_at
        col('u.role').eq('admin'),          // qualified with alias
      ])
    )
    ..orderBy(['u.name', 'created_at']);   // mix of qualified and unqualified

  // Analyze dependencies
  final dependencies = query.analyzeDependencies();

  print('Tables: ${dependencies.tables}');
  print('Uses Wildcard: ${dependencies.usesWildcard}');
  print('Columns:');
  for (final col in dependencies.columns) {
    print('  - Table: "${col.table}", Column: "${col.column}", Qualified Name: "${col.qualifiedName}"');
  }

  print('\n=== Expected Results ===');
  print('All unqualified columns should resolve to "users" table');
  print('All alias-qualified columns (u.*) should resolve to "users" table');
  print('This demonstrates proper SQL scoping with the AnalysisContext stack');
}