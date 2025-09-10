import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('ViewBuilder Tests', () {
    group('Basic View Creation', () {
      test('can create a simple view from table', () {
        final view = ViewBuilder.simple('user_view', 'users');
        
        expect(view.name, equals('user_view'));
        expect(view.queryBuilder, isNotNull);
        expect(view.isRawSql, isFalse);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_view AS'));
        expect(sql, contains('SELECT *'));
        expect(sql, contains('FROM users'));
      });

      test('can create a filtered view', () {
        final view = ViewBuilder.simple('active_users', 'users', 'active = 1');
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW active_users AS'));
        expect(sql, contains('WHERE active = 1'));
      });

      test('can create view with specific columns', () {
        final view = ViewBuilder.withColumns('user_summary', 'users', ['id', 'username', 'email']);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_summary AS'));
        expect(sql, contains('SELECT id, username, email'));
        expect(sql, contains('FROM users'));
      });

      test('can create view from raw SQL', () {
        final view = ViewBuilder.fromSql('custom_view', 'SELECT * FROM users WHERE age > 18');
        
        expect(view.isRawSql, isTrue);
        expect(view.queryBuilder, isNull);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW custom_view AS'));
        expect(sql, contains('SELECT * FROM users WHERE age > 18'));
      });
    });

    group('Expression-based Views', () {
      test('can create view with expressions and aliases', () {
        final expressions = [
          ExpressionBuilder.column('id'),
          ExpressionBuilder.column('username').as('name'),
          ExpressionBuilder.function('UPPER', ['email']).as('email_upper'),
          ExpressionBuilder.literal('Active').as('status'),
        ];

        final view = ViewBuilder.withExpressions('user_enhanced', 'users', expressions);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_enhanced AS'));
        expect(sql, contains('SELECT id, username AS name, UPPER(email) AS email_upper, \'Active\' AS status'));
      });

      test('can create view with aggregate functions', () {
        final view = Views.aggregated('user_stats', 'users', [
          Expressions.count.as('total_users'),
          Expressions.avg('age').as('avg_age'),
          Expressions.max('created_at').as('latest_signup'),
        ], null);

        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_stats AS'));
        expect(sql, contains('COUNT(*) AS total_users'));
        expect(sql, contains('AVG(age) AS avg_age'));
        expect(sql, contains('MAX(created_at) AS latest_signup'));
      });

      test('can create view with GROUP BY', () {
        final view = Views.aggregated('users_by_department', 'users', [
          ExpressionBuilder.column('department'),
          Expressions.count.as('user_count'),
        ], ['department']);

        final sql = view.toSql();
        expect(sql, contains('GROUP BY department'));
      });
    });

    group('Join-based Views', () {
      test('can create view with inner join', () {
        final view = Views.joined('user_posts', 'users', 'posts', 'users.id = posts.user_id');
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_posts AS'));
        expect(sql, contains('FROM users'));
        expect(sql, contains('INNER JOIN posts ON users.id = posts.user_id'));
      });

      test('can create view with complex joins and conditions', () {
        final view = ViewBuilder.withJoins('active_user_posts', (query) => 
          query
            .select([
              ExpressionBuilder.qualifiedColumn('users', 'username'),
              ExpressionBuilder.qualifiedColumn('posts', 'title'),
              ExpressionBuilder.qualifiedColumn('posts', 'created_at'),
            ])
            .from('users')
            .innerJoin('posts', 'users.id = posts.user_id')
            .leftJoin('user_profiles', 'users.id = user_profiles.user_id')
            .where('users.active = 1 AND posts.published = 1')
            .orderByColumn('posts.created_at', true)
        );

        final sql = view.toSql();
        expect(sql, contains('users.username, posts.title, posts.created_at'));
        expect(sql, contains('INNER JOIN posts ON users.id = posts.user_id'));
        expect(sql, contains('LEFT JOIN user_profiles ON users.id = user_profiles.user_id'));
        expect(sql, contains('WHERE users.active = 1 AND posts.published = 1'));
        expect(sql, contains('ORDER BY posts.created_at DESC'));
      });
    });

    group('Complex Query Features', () {
      test('can create view with subquery-like structure using QueryBuilder', () {
        final view = ViewBuilder('popular_posts', 
          QueryBuilder()
            .select([
              ExpressionBuilder.column('id'),
              ExpressionBuilder.column('title'),
              ExpressionBuilder.column('likes'),
            ])
            .from('posts')
            .where('likes > 100')
            .orderByColumn('likes', true)
            .limit(10)
        );

        final sql = view.toSql();
        expect(sql, contains('WHERE likes > 100'));
        expect(sql, contains('ORDER BY likes DESC'));
        expect(sql, contains('LIMIT 10'));
      });

      test('can create view with HAVING clause', () {
        final view = ViewBuilder('frequent_posters',
          QueryBuilder()
            .select([
              ExpressionBuilder.column('user_id'),
              Expressions.count.as('post_count'),
            ])
            .from('posts')
            .groupBy(['user_id'])
            .having('COUNT(*) > 5')
            .orderByColumn('post_count', true)
        );

        final sql = view.toSql();
        expect(sql, contains('GROUP BY user_id'));
        expect(sql, contains('HAVING COUNT(*) > 5'));
      });
    });

    group('Helper Methods', () {
      test('provides drop SQL statement', () {
        final view = ViewBuilder.simple('test_view', 'test_table');
        
        expect(view.dropSql(), equals('DROP VIEW IF EXISTS test_view'));
      });

      test('Views helper class provides convenient factory methods', () {
        expect(Views.all('all_users', 'users').name, equals('all_users'));
        expect(Views.filtered('active_users', 'users', 'active = 1').name, equals('active_users'));
        expect(Views.columns('user_names', 'users', ['username']).name, equals('user_names'));
        expect(Views.fromSql('raw_view', 'SELECT 1').name, equals('raw_view'));
      });
    });

    group('Error Handling', () {
      test('throws error for empty SELECT in QueryBuilder', () {
        final emptyQuery = QueryBuilder().from('users');
        final view = ViewBuilder('empty_view', emptyQuery);
        
        expect(() => view.toSql(), throwsStateError);
      });

      test('handles invalid query types gracefully', () {
        // Create a view with raw SQL that would cause an error
        final view = ViewBuilder.fromSql('invalid_view', '');
        
        // This should work fine for empty raw SQL
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW invalid_view AS'));
        expect(sql, contains(''));
      });
    });
  });

  group('QueryBuilder Tests', () {
    test('can build basic SELECT query', () {
      final query = QueryBuilder()
        .selectColumns(['id', 'name'])
        .from('users');

      final sql = query.toSql();
      expect(sql, equals('SELECT id, name\nFROM users'));
    });

    test('can build query with WHERE and ORDER BY', () {
      final query = QueryBuilder()
        .selectAll()
        .from('users')
        .where('age > 18')
        .orderByColumn('name');

      final sql = query.toSql();
      expect(sql, contains('WHERE age > 18'));
      expect(sql, contains('ORDER BY name'));
    });

    test('can build query with multiple joins', () {
      final query = QueryBuilder()
        .selectColumns(['u.name', 'p.title'])
        .from('users', 'u')
        .innerJoin('posts', 'u.id = p.user_id', 'p')
        .leftJoin('categories', 'p.category_id = c.id', 'c');

      final sql = query.toSql();
      expect(sql, contains('FROM users AS u'));
      expect(sql, contains('INNER JOIN posts AS p ON u.id = p.user_id'));
      expect(sql, contains('LEFT JOIN categories AS c ON p.category_id = c.id'));
    });

    test('can build query with complex WHERE conditions', () {
      final query = QueryBuilder()
        .selectAll()
        .from('users')
        .where('age > 18')
        .andWhere('active = 1')
        .orWhere('vip = 1');

      final sql = query.toSql();
      expect(sql, contains('WHERE ((age > 18) AND (active = 1)) OR (vip = 1)'));
    });

    test('can build query with GROUP BY and HAVING', () {
      final query = QueryBuilder()
        .select([
          ExpressionBuilder.column('department'),
          Expressions.count.as('emp_count')
        ])
        .from('employees')
        .groupBy(['department'])
        .having('COUNT(*) > 5');

      final sql = query.toSql();
      expect(sql, contains('GROUP BY department'));
      expect(sql, contains('HAVING COUNT(*) > 5'));
    });

    test('can build query with LIMIT and OFFSET', () {
      final query = QueryBuilder()
        .selectAll()
        .from('users')
        .limit(10, 20);

      final sql = query.toSql();
      expect(sql, contains('LIMIT 10 OFFSET 20'));
    });
  });

  group('ExpressionBuilder Tests', () {
    test('can create column expressions', () {
      final expr = ExpressionBuilder.column('username');
      expect(expr.toSql(), equals('username'));
    });

    test('can create qualified column expressions', () {
      final expr = ExpressionBuilder.qualifiedColumn('users', 'username');
      expect(expr.toSql(), equals('users.username'));
    });

    test('can create expressions with aliases', () {
      final expr = ExpressionBuilder.column('username').as('name');
      expect(expr.toSql(), equals('username AS name'));
    });

    test('can create literal expressions', () {
      expect(ExpressionBuilder.literal('hello').toSql(), equals("'hello'"));
      expect(ExpressionBuilder.literal(42).toSql(), equals('42'));
      expect(ExpressionBuilder.literal(true).toSql(), equals('1'));
      expect(ExpressionBuilder.literal(null).toSql(), equals('NULL'));
    });

    test('can create function expressions', () {
      final expr = ExpressionBuilder.function('UPPER', ['username']);
      expect(expr.toSql(), equals('UPPER(username)'));
    });

    test('common expressions work correctly', () {
      expect(Expressions.count.toSql(), equals('COUNT(*)'));
      expect(Expressions.sum('amount').toSql(), equals('SUM(amount)'));
      expect(Expressions.avg('score').toSql(), equals('AVG(score)'));
      expect(Expressions.all.toSql(), equals('*'));
    });
  });

  group('JoinBuilder Tests', () {
    test('can create different join types', () {
      expect(Joins.inner('posts').toSql(), equals('INNER JOIN posts'));
      expect(Joins.left('profiles').toSql(), equals('LEFT JOIN profiles'));
      expect(Joins.right('categories').toSql(), equals('RIGHT JOIN categories'));
      expect(Joins.fullOuter('logs').toSql(), equals('FULL OUTER JOIN logs'));
      expect(Joins.cross('tags').toSql(), equals('CROSS JOIN tags'));
    });

    test('can create joins with aliases and conditions', () {
      final join = Joins.inner('posts')
        .as('p')
        .on('users.id = p.user_id');
      
      expect(join.toSql(), equals('INNER JOIN posts AS p ON users.id = p.user_id'));
    });

    test('can create equi-joins', () {
      final join = Joins.left('profiles')
        .onEquals('users.id', 'profiles.user_id');
      
      expect(join.toSql(), equals('LEFT JOIN profiles ON users.id = profiles.user_id'));
    });
  });
}