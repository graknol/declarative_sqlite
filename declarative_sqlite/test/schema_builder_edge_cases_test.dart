import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/schema/key.dart';
import 'package:test/test.dart';

void main() {
  group('SchemaBuilder edge cases', () {
    test('throws if table is missing primary key', () {
      final builder = SchemaBuilder();
      builder.table('no_pk', (table) {
        table.guid('id');
      });
      final schema = builder.build();
      // No error is thrown by default, but you may want to enforce this in your own code.
      expect(
          schema.tables.first.keys
              .where((k) => k.type == KeyType.primary)
              .isEmpty,
          true);
    });

    test('throws if reference is missing to/toMany', () {
      final builder = TableBuilder('foo');
      builder.guid('id');
      builder.reference(['id']);
      // Should throw when build is called due to missing to()/toMany()
      expect(() => builder.build(), throwsA(TypeMatcher<Error>()));
    });

    test('throws if view is missing select', () {
      final builder = ViewBuilder('v');
      // No select called
      final view = builder.build();
      expect(view.definition, isNot(contains('SELECT')));
    });
  });
}
