import '../builders/query_builder.dart';
import '../builders/where_clause.dart';

/// Comprehensive example demonstrating the new Aliased-based QueryBuilder system
void demonstrateAliasedQueryBuilder() {
  print('=== Aliased QueryBuilder Demo ===\n');

  // Example 1: Basic query with table alias and mixed column references
  print('1. Basic query with table alias:');
  final query1 = QueryBuilder()
    ..from('users', 'u')           // Table with alias
    ..select('u.id')               // Qualified with alias
    ..select('name')               // Unqualified - should resolve to users.name
    ..select('email', 'user_email') // Unqualified with column alias
    ..select('u.created_at')       // Qualified with alias
    ..where(
      and([
        col('u.active').eq(true),
        col('created_at').gt('2023-01-01'), // Unqualified
      ])
    )
    ..orderBy(['u.name', 'created_at']);

  final (sql1, params1) = query1.build();
  print('SQL: $sql1');
  print('Parameters: $params1');

  final deps1 = query1.analyzeDependencies();
  print('Dependencies:');
  print('  Tables: ${deps1.tables}');
  print('  Columns:');
  for (final col in deps1.columns) {
    print('    - ${col.qualifiedName} (table: "${col.table}", column: "${col.column}")');
  }
  print('  Uses wildcard: ${deps1.usesWildcard}\n');

  // Example 2: Complex query with subquery and multiple aliases
  print('2. Complex query with subquery:');
  final query2 = QueryBuilder()
    ..from('orders', 'o')
    ..select('o.id')
    ..select('o.total')
    ..select('u.name', 'customer_name') // Will be added via JOIN
    ..selectSubQuery((sub) {
      sub
        ..from('order_items', 'oi')
        ..select('COUNT(*)')
        ..where(col('oi.order_id').eq(col('o.id')));
    }, 'item_count')
    ..where(
      and([
        col('o.status').eq('completed'),
        col('o.total').gt(100),
      ])
    )
    ..orderBy(['o.created_at'])
    ..groupBy(['o.id', 'u.name']);

  final (sql2, params2) = query2.build();
  print('SQL: $sql2');
  print('Parameters: $params2');

  final deps2 = query2.analyzeDependencies();
  print('Dependencies:');
  print('  Tables: ${deps2.tables}');
  print('  Columns:');
  for (final col in deps2.columns) {
    print('    - ${col.qualifiedName} (table: "${col.table}", column: "${col.column}")');
  }
  print('  Uses wildcard: ${deps2.usesWildcard}\n');

  // Example 3: Wildcard selection
  print('3. Wildcard selection:');
  final query3 = QueryBuilder()
    ..from('products', 'p')
    ..select('*')
    ..where(col('p.category').eq('electronics'));

  final (sql3, params3) = query3.build();
  print('SQL: $sql3');
  print('Parameters: $params3');

  final deps3 = query3.analyzeDependencies();
  print('Dependencies:');
  print('  Tables: ${deps3.tables}');
  print('  Uses wildcard: ${deps3.usesWildcard}');
  print('  Columns: ${deps3.columns.map((c) => c.qualifiedName).join(', ')}\n');

  print('=== Key Benefits of Aliased System ===');
  print('1. SQL Generation: Uses Aliased.toString() for clean, automatic alias handling');
  print('2. Dependency Analysis: Accesses .expression and .alias properties for precise analysis');
  print('3. Context Resolution: AnalysisContext properly resolves aliases to full table names');
  print('4. Type Safety: Aliased<T> provides compile-time safety for different expression types');
  print('5. Consistency: Same pattern for tables, columns, and future JOIN support');
}