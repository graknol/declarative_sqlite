import 'package:declarative_sqlite/src/builders/query_builder.dart';
import 'package:declarative_sqlite/src/builders/where_clause.dart';
import 'package:test/test.dart';

void main() {
  group('QueryBuilder', () {
    test('builds a simple SELECT * query', () {
      final builder = QueryBuilder().from('users');
      final (sql, params) = builder.build();
      expect(sql, 'SELECT * FROM users;');
      expect(params, isEmpty);
    });

    test('builds a query with specific columns', () {
      final builder = QueryBuilder().select('id').select('name').from('users');
      final (sql, params) = builder.build();
      expect(sql, 'SELECT id, name FROM users;');
      expect(params, isEmpty);
    });

    test('builds a query with table and column aliases', () {
      final builder = QueryBuilder()
          .select('u.id', 'user_id')
          .select('u.name')
          .from('users', 'u');
      final (sql, params) = builder.build();
      expect(sql, 'SELECT u.id AS user_id, u.name FROM users AS u;');
      expect(params, isEmpty);
    });

    test('throws StateError if from() is not called', () {
      final builder = QueryBuilder().select('id');
      expect(() => builder.build(), throwsA(isA<StateError>()));
    });

    test('builds a query with a simple WHERE clause', () {
      final builder = QueryBuilder().from('users').where(col('age').gt(18));
      final (sql, params) = builder.build();
      expect(sql, 'SELECT * FROM users WHERE age > ?;');
      expect(params, [18]);
    });

    test('builds a query with a complex WHERE clause', () {
      final builder = QueryBuilder().from('users').where(and([
            col('age').gte(18),
            or([
              col('name').like('A%'),
              col('status').eq('active'),
            ]),
          ]));
      final (sql, params) = builder.build();
      expect(sql,
          'SELECT * FROM users WHERE (age >= ? AND (name LIKE ? OR status = ?));');
      expect(params, [18, 'A%', 'active']);
    });

    test('builds a query with IS NULL and IS NOT NULL', () {
      final builder = QueryBuilder()
          .from('users')
          .where(or([col('email').nil, col('phone').notNil]));
      final (sql, params) = builder.build();
      expect(sql,
          'SELECT * FROM users WHERE (email IS NULL OR phone IS NOT NULL);');
      expect(params, isEmpty);
    });

    test('builds a query with ORDER BY', () {
      final builder =
          QueryBuilder().from('users').orderBy(['name DESC', 'age']);
      final (sql, params) = builder.build();
      expect(sql, 'SELECT * FROM users ORDER BY name DESC, age;');
      expect(params, isEmpty);
    });

    test('builds a query with GROUP BY', () {
      final builder = QueryBuilder()
          .select('status')
          .select('COUNT(id)', 'count')
          .from('users')
          .groupBy(['status']);
      final (sql, params) = builder.build();
      expect(
          sql, 'SELECT status, COUNT(id) AS count FROM users GROUP BY status;');
      expect(params, isEmpty);
    });

    test('builds a query with WHERE, GROUP BY, and ORDER BY', () {
      final builder = QueryBuilder()
          .select('status')
          .select('COUNT(id)', 'count')
          .from('users')
          .where(col('age').gt(18))
          .groupBy(['status']).orderBy(['count DESC']);
      final (sql, params) = builder.build();
      expect(sql,
          'SELECT status, COUNT(id) AS count FROM users WHERE age > ? GROUP BY status ORDER BY count DESC;');
      expect(params, [18]);
    });
  });
}
