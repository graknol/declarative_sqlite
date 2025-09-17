import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/builders/view_builder.dart';
import 'package:test/test.dart';

void main() {
  group('ViewBuilder with subquery', () {
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
  });
}
