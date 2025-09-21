import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/builders/view_builder.dart';
import 'package:test/test.dart';

void main() {
  group('ViewBuilder Assert Tests', () {
    test('should assert when multiple columns in single select() call', () {
      final viewBuilder = ViewBuilder('test_view');
      
      expect(
        () => viewBuilder.select('col1, col2'),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('Multiple columns in single select() call are not allowed'),
        )),
      );
    });

    test('should assert when join condition is string instead of WhereClause', () {
      final viewBuilder = ViewBuilder('test_view');
      viewBuilder.select('id').from('table1');
      
      expect(
        () => viewBuilder.innerJoin('table2', 'table1.id = table2.id'),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('Join condition cannot be null'),
        )),
      );
    });

    test('should assert when WHERE clause comes before FROM', () {
      final viewBuilder = ViewBuilder('test_view');
      viewBuilder.select('id');
      
      expect(
        () => viewBuilder.where(col('active').eq(1)),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('FROM clause must be specified before WHERE clause'),
        )),
      );
    });

    test('should assert when HAVING clause comes before GROUP BY', () {
      final viewBuilder = ViewBuilder('test_view');
      viewBuilder.select('id').from('table1');
      
      expect(
        () => viewBuilder.having('COUNT(*) > 5'),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('GROUP BY clause must be specified before HAVING clause'),
        )),
      );
    });

    test('should assert when table name is empty', () {
      expect(
        () => ViewBuilder(''),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('Table name cannot be empty'),
        )),
      );
    });

    test('should assert when FROM table name is empty', () {
      final viewBuilder = ViewBuilder('test_view');
      viewBuilder.select('id');
      
      expect(
        () => viewBuilder.from(''),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('Table name cannot be empty'),
        )),
      );
    });

    test('should assert when join table name is empty', () {
      final viewBuilder = ViewBuilder('test_view');
      viewBuilder.select('id').from('table1');
      
      expect(
        () => viewBuilder.innerJoin('', col('table1.id').eq(col('table2.id'))),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('Table name cannot be empty'),
        )),
      );
    });

    test('should assert when column expression is empty in select', () {
      final viewBuilder = ViewBuilder('test_view');
      
      expect(
        () => viewBuilder.select(''),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('Column expression cannot be empty'),
        )),
      );
    });

    test('should assert when no columns are selected before build', () {
      final viewBuilder = ViewBuilder('test_view');
      viewBuilder.from('table1');
      
      expect(
        () => viewBuilder.build(),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('At least one column must be selected'),
        )),
      );
    });

    test('should assert when no FROM clause before build', () {
      final viewBuilder = ViewBuilder('test_view');
      viewBuilder.select('id');
      
      expect(
        () => viewBuilder.build(),
        throwsA(isA<AssertionError>().having(
          (e) => e.message,
          'message',
          contains('FROM clause must be specified'),
        )),
      );
    });

    test('should allow valid individual select calls', () {
      final viewBuilder = ViewBuilder('test_view');
      
      expect(
        () => viewBuilder.select('orders.id')
                        .select('orders.created_at')
                        .select('customers.first_name || " " || customers.last_name', 'customer_name')
                        .from('orders'),
        returnsNormally,
      );
    });

    test('should allow valid WhereClause join conditions', () {
      final viewBuilder = ViewBuilder('test_view');
      
      expect(
        () => viewBuilder.select('orders.id')
                        .from('orders')
                        .innerJoin('customers', col('orders.customer_id').eq(col('customers.id'))),
        returnsNormally,
      );
    });

    test('should allow valid order of clauses', () {
      final viewBuilder = ViewBuilder('test_view');
      
      expect(
        () => viewBuilder.select('orders.id')
                        .select('COUNT(*)', 'item_count')
                        .from('orders')
                        .leftJoin('order_items', col('orders.id').eq(col('order_items.order_id')))
                        .where(col('orders.status').eq('active'))
                        .groupBy(['orders.id'])
                        .having('COUNT(*) > 0')
                        .orderBy(['orders.id']),
        returnsNormally,
      );
    });
  });
}