import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

/// Mock schema provider for testing
class MockSchemaProvider implements SchemaProvider {
  final Map<String, Set<String>> _tableColumns = {
    'users': {'id', 'name', 'username', 'department', 'active'},
    'posts': {'id', 'title', 'author_id', 'category_id', 'published_date', 'created_at', 'status'},
    'comments': {'id', 'content', 'post_id', 'user_id'},
    'categories': {'id', 'name'},
    'subscriptions': {'id', 'user_id', 'active', 'created_at'},
    'table_a': {'id', 'value'},
    'table_b': {'id', 'data'},
    'table_c': {'id', 'info', 'ref_id'},
    // Views can now be included since View class has structured column information
    'user_posts_view': {'user_id', 'username', 'post_title', 'post_count'},
    'active_subscriptions_view': {'user_id', 'user_name', 'subscription_date'},
  };

  @override
  bool tableHasColumn(String tableName, String columnName) {
    return _tableColumns[tableName]?.contains(columnName) ?? false;
  }

  @override
  List<String> getTablesWithColumn(String columnName) {
    return _tableColumns.entries
        .where((entry) => entry.value.contains(columnName))
        .map((entry) => entry.key)
        .toList();
  }
}

void main() {
  group('QueryDependencyAnalyzer Tests', () {
    late QueryDependencyAnalyzer analyzer;
    late MockSchemaProvider schema;

    setUp(() {
      schema = MockSchemaProvider();
      analyzer = QueryDependencyAnalyzer(schema);
    });

    test('should analyze simple query with basic JOIN', () {
      // Build a query: SELECT u.name, p.title FROM users u INNER JOIN posts p ON u.id = p.user_id WHERE u.active = ?
      final query = QueryBuilder()
          .select('u.name')
          .select('p.title')
          .from('users', 'u')
          .innerJoin('posts', col('u.id').eq(col('p.user_id')), 'p')
          .where(col('u.active').eq(true));

      final dependencies = analyzer.analyzeQuery(query);

      // Should have both tables
      expect(dependencies.tables, containsAll(['users AS u', 'posts AS p']));

      // Should have specific columns
      expect(dependencies.columns, hasLength(greaterThanOrEqualTo(4)));
      expect(
          dependencies.columns
              .any((c) => c.table == 'users' && c.column == 'name'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'posts' && c.column == 'title'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'users' && c.column == 'id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'posts' && c.column == 'user_id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'users' && c.column == 'active'),
          isTrue);

      expect(dependencies.usesWildcard, isFalse);
    });

    test('should analyze complex query with multiple JOINs and subquery', () {
      // Build a complex query with multiple joins and a subquery
      // SELECT u.username, p.title, c.content, cat.name as category_name
      // FROM users u
      // INNER JOIN posts p ON u.id = p.author_id
      // LEFT JOIN comments c ON p.id = c.post_id
      // INNER JOIN categories cat ON p.category_id = cat.id
      // WHERE u.id IN (SELECT user_id FROM subscriptions WHERE active = ?)
      // AND p.published_date > ?
      // ORDER BY p.created_at DESC

      final subQuery = QueryBuilder()
          .select('user_id')
          .from('subscriptions')
          .where(col('active').eq(true));

      final mainQuery = QueryBuilder()
          .select('u.username')
          .select('p.title')
          .select('c.content')
          .select('cat.name', 'category_name')
          .from('users', 'u')
          .innerJoin('posts', col('u.id').eq(col('p.author_id')), 'p')
          .leftJoin('comments', col('p.id').eq(col('c.post_id')), 'c')
          .innerJoin(
              'categories', col('p.category_id').eq(col('cat.id')), 'cat')
          .where(and([
            col('u.id').inSubQuery(subQuery),
            col('p.published_date').gt(DateTime.now())
          ]))
          .orderBy(['p.created_at DESC']);

      final dependencies = analyzer.analyzeQuery(mainQuery);

      // Should have all main tables
      expect(
          dependencies.tables,
          containsAll([
            'users AS u',
            'posts AS p',
            'comments AS c',
            'categories AS cat',
            'subscriptions' // From subquery
          ]));

      // Should have all referenced columns
      final expectedColumns = [
        // SELECT columns
        QueryDependencyColumn('users', 'username'),
        QueryDependencyColumn('posts', 'title'),
        QueryDependencyColumn('comments', 'content'),
        QueryDependencyColumn('categories', 'name'),

        // JOIN conditions
        QueryDependencyColumn('users', 'id'),
        QueryDependencyColumn('posts', 'author_id'),
        QueryDependencyColumn('posts', 'id'),
        QueryDependencyColumn('comments', 'post_id'),
        QueryDependencyColumn('posts', 'category_id'),
        QueryDependencyColumn('categories', 'id'),

        // WHERE conditions
        QueryDependencyColumn('posts', 'published_date'),

        // Subquery columns
        QueryDependencyColumn('subscriptions', 'user_id'),
        QueryDependencyColumn('subscriptions', 'active'),

        // ORDER BY columns
        QueryDependencyColumn('posts', 'created_at'),
      ];

      for (final expectedCol in expectedColumns) {
        expect(
            dependencies.columns.any((c) =>
                c.table == expectedCol.table && c.column == expectedCol.column),
            isTrue,
            reason:
                'Expected column ${expectedCol.table}.${expectedCol.column} not found');
      }

      expect(dependencies.usesWildcard, isFalse);
    });

    test('should analyze query with wildcard and table aliases', () {
      // SELECT u.*, p.title FROM users u LEFT JOIN posts p ON u.id = p.user_id
      final query = QueryBuilder()
          .select('u.*')
          .select('p.title')
          .from('users', 'u')
          .leftJoin('posts', col('u.id').eq(col('p.user_id')), 'p');

      final dependencies = analyzer.analyzeQuery(query);

      expect(dependencies.tables, containsAll(['users AS u', 'posts AS p']));
      expect(dependencies.usesWildcard, isTrue);

      // Should still track specific columns from JOIN and non-wildcard SELECT
      expect(
          dependencies.columns
              .any((c) => c.table == 'posts' && c.column == 'title'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'users' && c.column == 'id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'posts' && c.column == 'user_id'),
          isTrue);
    });

    test('should analyze nested subqueries with different alias scopes', () {
      // Test that alias resolution works correctly in nested contexts
      // SELECT u.name FROM users u WHERE u.id IN (
      //   SELECT p.author_id FROM posts p WHERE p.category_id IN (
      //     SELECT c.id FROM categories c WHERE c.name = ?
      //   )
      // )

      final innerSubquery = QueryBuilder()
          .select('c.id')
          .from('categories', 'c')
          .where(col('c.name').eq('technology'));

      final middleSubquery = QueryBuilder()
          .select('p.author_id')
          .from('posts', 'p')
          .where(col('p.category_id').inSubQuery(innerSubquery));

      final mainQuery = QueryBuilder()
          .select('u.name')
          .from('users', 'u')
          .where(col('u.id').inSubQuery(middleSubquery));

      final dependencies = analyzer.analyzeQuery(mainQuery);

      expect(dependencies.tables,
          containsAll(['users AS u', 'posts AS p', 'categories AS c']));

      // Verify all columns are properly resolved despite alias reuse
      expect(
          dependencies.columns
              .any((c) => c.table == 'users' && c.column == 'name'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'users' && c.column == 'id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'posts' && c.column == 'author_id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'posts' && c.column == 'category_id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'categories' && c.column == 'id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'categories' && c.column == 'name'),
          isTrue);
    });

    test('should handle CROSS JOIN and FULL OUTER JOIN', () {
      // Test different join types
      final query = QueryBuilder()
          .select('a.value')
          .select('b.data')
          .select('c.info')
          .from('table_a', 'a')
          .crossJoin('table_b', 'b')
          .fullOuterJoin('table_c', col('a.id').eq(col('c.ref_id')), 'c');

      final dependencies = analyzer.analyzeQuery(query);

      expect(dependencies.tables,
          containsAll(['table_a AS a', 'table_b AS b', 'table_c AS c']));
      expect(
          dependencies.columns
              .any((c) => c.table == 'table_a' && c.column == 'value'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'table_b' && c.column == 'data'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'table_c' && c.column == 'info'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'table_a' && c.column == 'id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'table_c' && c.column == 'ref_id'),
          isTrue);
    });

    test('should analyze query with GROUP BY and HAVING clauses', () {
      // SELECT u.department, COUNT(*) as user_count
      // FROM users u
      // INNER JOIN posts p ON u.id = p.author_id
      // WHERE p.status = ?
      // GROUP BY u.department
      // HAVING COUNT(*) > ?
      // ORDER BY user_count DESC

      final query = QueryBuilder()
          .select('u.department')
          .select('COUNT(*)', 'user_count')
          .from('users', 'u')
          .innerJoin('posts', col('u.id').eq(col('p.author_id')), 'p')
          .where(col('p.status').eq(col('published')))
          .groupBy(['u.department'])
          .having('COUNT(*) > ?')
          .orderBy(['user_count DESC']);

      final dependencies = analyzer.analyzeQuery(query);

      expect(dependencies.tables, containsAll(['users AS u', 'posts AS p']));

      // Should include columns from all clauses
      expect(
          dependencies.columns
              .any((c) => c.table == 'users' && c.column == 'department'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'users' && c.column == 'id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'posts' && c.column == 'author_id'),
          isTrue);
      expect(
          dependencies.columns
              .any((c) => c.table == 'posts' && c.column == 'status'),
          isTrue);
    });
  });

  group('AnalysisContext Tests', () {
    test('should resolve aliases correctly with nested scopes', () {
      final context = AnalysisContext();

      // Main query scope
      context.addTable('users', alias: 'u');
      context.addTable('posts', alias: 'p');

      expect(context.resolveTable('u'), equals('users'));
      expect(context.resolveTable('p'), equals('posts'));
      expect(context.resolveTable('users'), equals('users'));

      // Enter subquery scope
      context.pushLevel();
      context.addTable('categories', alias: 'u'); // Shadow 'u' alias

      expect(context.resolveTable('u'), equals('categories')); // Closest wins
      expect(context.resolveTable('p'), equals('posts')); // Still accessible

      // Exit subquery scope
      context.popLevel();

      expect(context.resolveTable('u'), equals('users')); // Back to original
      expect(context.resolveTable('p'), equals('posts'));
    });

    test('should resolve unqualified columns using schema information', () {
      final schema = MockSchemaProvider();
      final context = AnalysisContext(schema);

      // Set up context with multiple tables
      context.addTable('users', alias: 'u');
      context.addTable('posts', alias: 'p');

      // Test column resolution - 'name' exists in both users and categories,
      // but only users is in context, so it should resolve to users
      expect(context.resolveUnqualifiedColumn('name'), equals('users'));
      
      // Test column that only exists in posts
      expect(context.resolveUnqualifiedColumn('title'), equals('posts'));
      
      // Test column that doesn't exist in any table in context
      expect(context.resolveUnqualifiedColumn('nonexistent'), isNull);

      // Add categories to context and test precedence
      context.addTable('categories', alias: 'cat');
      // 'name' exists in both users and categories, but categories was added last
      // so it should be found first in the available tables list
      expect(context.resolveUnqualifiedColumn('name'), equals('categories'));
    });

    test('should fall back to heuristics when no schema is provided', () {
      final context = AnalysisContext(); // No schema

      context.addTable('users', alias: 'u');
      context.addTable('posts', alias: 'p');

      // Without schema, should fall back to first table in current level
      expect(context.resolveUnqualifiedColumn('any_column'), equals('users'));
    });

    test('should resolve columns in views using structured view information', () {
      final schema = MockSchemaProvider();
      final context = AnalysisContext(schema);

      // Set up context with a view and tables
      context.addTable('user_posts_view', alias: 'upv');
      context.addTable('users', alias: 'u');

      // Test column that exists in the view
      expect(context.resolveUnqualifiedColumn('post_count'), equals('user_posts_view'));
      
      // Test column that exists in both view and table - view should win (added first)
      expect(context.resolveUnqualifiedColumn('user_id'), equals('user_posts_view'));
      
      // Test column that only exists in regular table
      expect(context.resolveUnqualifiedColumn('department'), equals('users'));
    });
  });
}
