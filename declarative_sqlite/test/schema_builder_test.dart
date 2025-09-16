import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/schema/key.dart';
import 'package:declarative_sqlite/src/schema/reference.dart';
import 'package:test/test.dart';

dynamic _dummySubQueryBuilder(dynamic sub) => null;
dynamic _dummyConditionBuilder(dynamic cond) => null;

void main() {
  group('SchemaBuilder', () {
    test('can build schema with tables and views', () {
      final builder = SchemaBuilder();
      builder.table('users', (table) {
        table.guid('id').notNull();
        table.text('name').notNull();
        table.key(['id']).primary();
      });
      builder.view('user_view', (view) {
        view.select('id').select('name').from('users');
      });
      final schema = builder.build();
      expect(schema.tables.length, 1);
      expect(schema.tables.first.name, 'users');
      expect(schema.views.length, 1);
      expect(schema.views.first.name, 'user_view');
    });
    test('SchemaBuilder creates a table with a fileset column', () {
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('files', (table) {
        table.fileset('document');
      });
      final schema = schemaBuilder.build();

      expect(schema.tables.length, 2);
      final filesTable = schema.tables.firstWhere((t) => t.name == 'files');
      expect(filesTable.name, 'files');
      expect(filesTable.columns.any((c) => c.name == 'document'), isTrue);
      final column = filesTable.columns.firstWhere((c) => c.name == 'document');
      expect(column.logicalType, 'fileset');
      expect(column.type, 'TEXT');

      final systemFilesTable =
          schema.tables.firstWhere((t) => t.name == '__files');
      expect(systemFilesTable, isNotNull);
      expect(systemFilesTable.columns.length, 9); // 6 + 3 system columns
    });
  });
  group('TableBuilder', () {
    test('can build table with columns, keys, and references', () {
      final builder = TableBuilder('orders');
      builder.guid('id').notNull();
      builder.text('customer_id').notNull();
      builder.real('total').notNull();
      builder.key(['id']).primary();
      builder.reference(['customer_id']).to('customer', ['id']);
      final table = builder.build();
      expect(table.name, 'orders');
      expect(table.columns.length, 6);
      expect(table.keys.length, 1);
      expect(table.references.length, 1);
      expect(table.references.first.foreignTable, 'customer');
    });

    test('min constraint is added to column definition', () {
      final builder = TableBuilder('products');
      builder.integer('quantity').min(0);
      final table = builder.build();
      final column = table.columns.firstWhere((c) => c.name == 'quantity');
      expect(column.minValue, 0);
    });

    test('maxLength constraint is added to column definition', () {
      final builder = TableBuilder('products');
      builder.text('name').maxLength(50);
      final table = builder.build();
      final column = table.columns.firstWhere((c) => c.name == 'name');
      expect(column.maxLength, 50);
    });

    test('date column is created with TEXT type', () {
      final builder = TableBuilder('events');
      builder.date('start_date');
      final table = builder.build();
      final column = table.columns.firstWhere((c) => c.name == 'start_date');
      expect(column.logicalType, 'date');
      expect(column.type, 'TEXT');
    });
  });

  group('ColumnBuilder', () {
    test('can set notNull, parent, lww', () {
      final col = TextColumnBuilder('foo')
        ..notNull()
        ..parent()
        ..lww();
      final built = col.build();
      expect(built.isNotNull, true);
      expect(built.isParent, true);
      expect(built.isLww, true);
    });
  });

  group('KeyBuilder', () {
    test('can set primary and index', () {
      final key = KeyBuilder(['id']);
      key.primary();
      final built = key.build();
      expect(built.type, KeyType.primary);
      key.index();
      final built2 = key.build();
      expect(built2.type, KeyType.indexed);
    });
  });

  group('ReferenceBuilder', () {
    test('can set to and toMany', () {
      final ref = ReferenceBuilder(['foo_id']);
      ref.to('bar', ['id']);
      final built = ref.build();
      expect(built.type, ReferenceType.toOne);
      expect(built.foreignTable, 'bar');
      ref.toMany('baz', ['id']);
      final built2 = ref.build();
      expect(built2.type, ReferenceType.toMany);
      expect(built2.foreignTable, 'baz');
    });
  });

  group('ViewBuilder', () {
    test('can build simple view', () {
      final builder = ViewBuilder('v');
      builder.select('foo').from('bar');
      final view = builder.build();
      expect(view.name, 'v');
      expect(view.definition, contains('SELECT foo'));
      expect(view.definition, contains('FROM bar'));
    });
    test('can add selectSubQuery and where', () {
      final builder = ViewBuilder('v2');
      builder
          .select('foo')
          .selectSubQuery(_dummySubQueryBuilder, 'cnt')
          .from('bar')
          .where(_dummyConditionBuilder);
      final view = builder.build();
      expect(view.definition, contains('SELECT foo'));
      expect(view.definition, contains('AS cnt'));
      expect(view.definition, contains('WHERE ...'));
    });
  });
}
