import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('ViewBuilder Tests', () {
    group('Static Factory Methods', () {
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

      test('can create view with expressions and aliases', () {
        final expressions = [
          ExpressionBuilder.column('id'),
          ExpressionBuilder.column('username').as('name'),
          ExpressionBuilder.function('UPPER', ['email']).as('email_upper'),
        ];
        
        final view = ViewBuilder.withExpressions('user_enhanced', 'users', expressions);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_enhanced AS'));
        expect(sql, contains('username AS name'));
        expect(sql, contains('UPPER(email) AS email_upper'));
      });

      test('can create complex view with joins', () {
        final view = ViewBuilder.withJoins('complex_view', (query) =>
          query
            .select([
              ExpressionBuilder.qualifiedColumn('u', 'id'),
              ExpressionBuilder.qualifiedColumn('u', 'username'),
              ExpressionBuilder.qualifiedColumn('p', 'title'),
            ])
            .from('users', 'u')
            .innerJoin('posts', 'u.id = p.user_id', 'p')
            .where('u.active = 1')
            .orderBy(['u.username'])
        );
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW complex_view AS'));
        expect(sql, contains('FROM users u'));
        expect(sql, contains('INNER JOIN posts p ON u.id = p.user_id'));
        expect(sql, contains('WHERE u.active = 1'));
        expect(sql, contains('ORDER BY u.username'));
      });

      test('can create view with raw SQL', () {
        final view = ViewBuilder.fromSql('raw_view', 'SELECT * FROM users WHERE age > 18');
        
        expect(view.name, equals('raw_view'));
        expect(view.queryBuilder, isNull);
        expect(view.isRawSql, isTrue);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW raw_view AS'));
        expect(sql, contains('SELECT * FROM users WHERE age > 18'));
      });
    });

    group('Legacy Views Helper Class', () {
      test('Views.all creates simple view', () {
        final view = Views.all('all_users', 'users');
        
        expect(view.name, equals('all_users'));
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW all_users AS'));
        expect(sql, contains('SELECT *'));
        expect(sql, contains('FROM users'));
      });

      test('Views.filtered creates filtered view', () {
        final view = Views.filtered('active_users', 'users', 'active = 1');
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW active_users AS'));
        expect(sql, contains('WHERE active = 1'));
      });

      test('Views.columns creates view with specific columns', () {
        final view = Views.columns('user_summary', 'users', ['id', 'username']);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_summary AS'));
        expect(sql, contains('SELECT id, username'));
        expect(sql, contains('FROM users'));
      });

      test('Views.aggregated creates view with aggregation', () {
        final aggregates = [
          Expressions.count.as('user_count'),
          Expressions.avg('age').as('avg_age'),
        ];
        
        final view = Views.aggregated('user_stats', 'users', aggregates, ['active']);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_stats AS'));
        expect(sql, contains('COUNT(*) AS user_count'));
        expect(sql, contains('AVG(age) AS avg_age'));
        expect(sql, contains('GROUP BY active'));
      });

      test('Views.joined creates view with join', () {
        final selectExpressions = [
          ExpressionBuilder.qualifiedColumn('u', 'username'),
          ExpressionBuilder.qualifiedColumn('p', 'title'),
        ];
        
        final view = Views.joined('user_posts', 'users', 'posts', 'users.id = posts.user_id', selectExpressions);
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW user_posts AS'));
        expect(sql, contains('FROM users'));
        expect(sql, contains('INNER JOIN posts ON users.id = posts.user_id'));
        expect(sql, contains('u.username, p.title'));
      });

      test('Views.fromSql creates view from raw SQL', () {
        final view = Views.fromSql('custom_view', 'SELECT COUNT(*) as total FROM users');
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW custom_view AS'));
        expect(sql, contains('SELECT COUNT(*) as total FROM users'));
      });
    });

    group('View Properties and Validation', () {
      test('view has correct name property', () {
        final view = ViewBuilder.simple('test_view', 'users');
        expect(view.name, equals('test_view'));
      });

      test('query-based view has queryBuilder property', () {
        final view = ViewBuilder.simple('test_view', 'users');
        expect(view.queryBuilder, isNotNull);
        expect(view.isRawSql, isFalse);
      });

      test('raw SQL view has correct properties', () {
        final view = ViewBuilder.fromSql('raw_view', 'SELECT 1');
        expect(view.queryBuilder, isNull);
        expect(view.isRawSql, isTrue);
      });
    });

    group('View SQL Generation', () {
      test('generates correct SQL format', () {
        final view = ViewBuilder.simple('test_view', 'users', 'active = 1');
        
        final sql = view.toSql();
        expect(sql, startsWith('CREATE VIEW test_view AS\n'));
        expect(sql, contains('SELECT *'));
        expect(sql, contains('FROM users'));
        expect(sql, contains('WHERE active = 1'));
      });

      test('handles view with no WHERE clause', () {
        final view = ViewBuilder.simple('all_users', 'users');
        
        final sql = view.toSql();
        expect(sql, contains('CREATE VIEW all_users AS'));
        expect(sql, contains('SELECT *'));
        expect(sql, contains('FROM users'));
        expect(sql.toLowerCase(), isNot(contains('where')));
      });
    });
  });
}