import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/builders/view_builder.dart';
import 'package:test/test.dart';

void main() {
  group('ViewBuilder with QueryBuilder integration', () {
    test('can build a view with a subquery in the FROM clause', () {
      final viewBuilder = ViewBuilder('my_view');
      viewBuilder.select('id').select('name').fromSubQuery((subQuery) {
        subQuery
            .select('id')
            .select('name')
            .from('users')
            .where(col('active').eq(1));
      }, 'active_users');

      final view = viewBuilder.build();

      const expectedSql =
          'SELECT id, name FROM (SELECT id, name FROM users WHERE active = ?) AS active_users';
      expect(view.definition, equals(expectedSql));
    });

    test('can build a view with WHERE clause using WhereClause', () {
      final viewBuilder = ViewBuilder('active_users');
      viewBuilder
          .select('id')
          .select('name')
          .from('users')
          .where(col('active').eq(1));

      final view = viewBuilder.build();
      expect(view.definition, equals('SELECT id, name FROM users WHERE active = ?'));
    });

    test('can build a view with complex WHERE conditions', () {
      final viewBuilder = ViewBuilder('filtered_users');
      viewBuilder
          .select('id')
          .select('name')
          .from('users')
          .where(and([
            col('active').eq(1),
            or([
              col('age').gte(18),
              col('status').eq('premium')
            ])
          ]));

      final view = viewBuilder.build();
      expect(view.definition, contains('WHERE (active = ? AND (age >= ? OR status = ?))'));
    });

    test('can build a view with JOINs', () {
      final viewBuilder = ViewBuilder('user_posts');
      viewBuilder
          .select('u.name')
          .select('p.title')
          .from('users', 'u')
          .innerJoin('posts', 'u.id = p.user_id', 'p')
          .where(col('u.active').eq(1));

      final view = viewBuilder.build();
      expect(view.definition, contains('INNER JOIN posts AS p ON u.id = p.user_id'));
      expect(view.definition, contains('WHERE u.active = ?'));
    });

    test('can build a view with subquery in SELECT clause', () {
      final viewBuilder = ViewBuilder('users_with_counts');
      viewBuilder
          .select('id')
          .select('name')
          .selectSubQuery((sub) {
            sub.select('COUNT(*)')
               .from('posts')
               .where(col('posts.user_id').eq(col('users.id')));
          }, 'post_count')
          .from('users');

      final view = viewBuilder.build();
      expect(view.definition, contains('(SELECT COUNT(*) FROM posts WHERE posts.user_id = users.id) AS post_count'));
    });

    test('can build a view with GROUP BY and HAVING', () {
      final viewBuilder = ViewBuilder('user_stats');
      viewBuilder
          .select('user_id')
          .select('COUNT(*)', 'post_count')
          .from('posts')
          .groupBy(['user_id'])
          .having('COUNT(*) > 5')
          .orderBy(['post_count DESC']);

      final view = viewBuilder.build();
      expect(view.definition, contains('GROUP BY user_id'));
      expect(view.definition, contains('HAVING COUNT(*) > 5'));
      expect(view.definition, contains('ORDER BY post_count DESC'));
    });

    test('can build a view with multiple JOIN types', () {
      final viewBuilder = ViewBuilder('comprehensive_view');
      viewBuilder
          .select('u.name')
          .select('p.title')
          .select('c.content')
          .from('users', 'u')
          .leftJoin('posts', 'u.id = p.user_id', 'p')
          .rightJoin('comments', 'p.id = c.post_id', 'c')
          .where(col('u.active').eq(1));

      final view = viewBuilder.build();
      expect(view.definition, contains('LEFT JOIN posts AS p ON u.id = p.user_id'));
      expect(view.definition, contains('RIGHT JOIN comments AS c ON p.id = c.post_id'));
    });

    test('can build a view with complex JOIN conditions using WhereClause', () {
      final viewBuilder = ViewBuilder('complex_join_view');
      viewBuilder
          .select('u.name')
          .select('p.title')
          .from('users', 'u')
          .leftJoin('posts', and([
            col('u.id').eq(col('p.user_id')),
            col('p.published').eq(1),
            col('p.created_at').gt('2024-01-01')
          ]), 'p')
          .where(col('u.active').eq(1));

      final view = viewBuilder.build();
      expect(view.definition, contains('LEFT JOIN posts AS p ON (u.id = p.user_id AND p.published = ? AND p.created_at > ?)'));
      expect(view.definition, contains('WHERE u.active = ?'));
    });

    test('can build a view with OR conditions in JOIN', () {
      final viewBuilder = ViewBuilder('flexible_join_view');
      viewBuilder
          .select('u.name')
          .select('p.title')
          .from('users', 'u')
          .innerJoin('posts', or([
            col('u.id').eq(col('p.user_id')),
            col('u.id').eq(col('p.author_id'))
          ]), 'p')
          .where(col('u.active').eq(1));

      final view = viewBuilder.build();
      expect(view.definition, contains('INNER JOIN posts AS p ON (u.id = p.user_id OR u.id = p.author_id)'));
    });
  });

  group('QueryBuilder enhancements', () {
    test('can build query with JOINs', () {
      final builder = QueryBuilder();
      final (sql, params) = builder
          .select('u.name')
          .select('p.title')
          .from('users', 'u')
          .leftJoin('posts', 'u.id = p.user_id', 'p')
          .where(col('u.active').eq(1))
          .build();

      expect(sql, contains('LEFT JOIN posts AS p ON u.id = p.user_id'));
      expect(sql, contains('WHERE u.active = ?'));
      expect(params, equals([1]));
    });

    test('can build query with HAVING clause', () {
      final builder = QueryBuilder();
      final (sql, params) = builder
          .select('user_id')
          .select('COUNT(*)', 'count')
          .from('posts')
          .groupBy(['user_id'])
          .having('COUNT(*) > 5')
          .build();

      expect(sql, contains('HAVING COUNT(*) > 5'));
    });

    test('can build query with subquery in SELECT', () {
      final builder = QueryBuilder();
      final (sql, params) = builder
          .select('id')
          .select('name')
          .selectSubQuery((sub) {
            sub.select('COUNT(*)')
               .from('posts')
               .where(col('posts.user_id').eq(col('users.id')));
          }, 'post_count')
          .from('users')
          .build();

      expect(sql, contains('(SELECT COUNT(*) FROM posts WHERE posts.user_id = users.id) AS post_count'));
    });

    test('can build query with complex JOIN conditions using WhereClause', () {
      final builder = QueryBuilder();
      final (sql, params) = builder
          .select('u.name')
          .select('p.title')
          .from('users', 'u')
          .leftJoin('posts', and([
            col('u.id').eq(col('p.user_id')),
            col('p.published').eq(1),
            col('p.created_at').gt('2024-01-01')
          ]), 'p')
          .where(col('u.active').eq(1))
          .build();

      expect(sql, contains('LEFT JOIN posts AS p ON (u.id = p.user_id AND p.published = ? AND p.created_at > ?)'));
      expect(sql, contains('WHERE u.active = ?'));
      expect(params, equals([1, '2024-01-01', 1]));
    });

    test('can build query with mixed join condition types', () {
      final builder = QueryBuilder();
      final (sql, params) = builder
          .select('u.name')
          .select('p.title')
          .select('c.content')
          .from('users', 'u')
          .leftJoin('posts', 'u.id = p.user_id', 'p')  // String condition
          .innerJoin('comments', and([                  // WhereClause condition
            col('p.id').eq(col('c.post_id')),
            col('c.approved').eq(1)
          ]), 'c')
          .where(col('u.active').eq(1))
          .build();

      expect(sql, contains('LEFT JOIN posts AS p ON u.id = p.user_id'));
      expect(sql, contains('INNER JOIN comments AS c ON (p.id = c.post_id AND c.approved = ?)'));
      expect(params, equals([1, 1]));
    });
  });
}
