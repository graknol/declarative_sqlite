import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('DeclarativeSqlite', () {
    test('can create a simple schema', () {
      final schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .text('email', (col) => col.unique()));

      expect(schema.tableCount, equals(1));
      expect(schema.tableNames, contains('users'));
      expect(schema.hasTable('users'), isTrue);
      expect(schema.hasTable('nonexistent'), isFalse);
    });

    test('can generate SQL for table creation', () {
      final table = TableBuilder('test_table')
          .integer('id', (col) => col.primaryKey())
          .text('name', (col) => col.notNull())
          .real('score');

      final sql = table.toSql();
      expect(sql, contains('CREATE TABLE test_table'));
      expect(sql, contains('id INTEGER PRIMARY KEY'));
      expect(sql, contains('name TEXT NOT NULL'));
      expect(sql, contains('score REAL'));
    });

    test('can create indices on tables', () {
      final table = TableBuilder('users')
          .autoIncrementPrimaryKey('id')
          .text('email', (col) => col.unique())
          .index('idx_email', ['email']);

      final indexSql = table.indexSqlStatements();
      expect(indexSql, hasLength(1));
      expect(indexSql.first, contains('CREATE INDEX idx_email ON users (email)'));
    });

    test('supports different data types', () {
      final table = TableBuilder('data_types')
          .integer('int_col')
          .real('real_col')
          .text('text_col')
          .blob('blob_col');

      final sql = table.toSql();
      expect(sql, contains('int_col INTEGER'));
      expect(sql, contains('real_col REAL'));
      expect(sql, contains('text_col TEXT'));
      expect(sql, contains('blob_col BLOB'));
    });

    test('can create composite indices', () {
      final table = TableBuilder('users')
          .text('first_name')
          .text('last_name')
          .index('idx_full_name', ['first_name', 'last_name'], unique: true);

      final indexSql = table.indexSqlStatements();
      expect(indexSql.first, contains('CREATE UNIQUE INDEX idx_full_name ON users (first_name, last_name)'));
    });

    test('validates column constraints', () {
      final column = ColumnBuilder('test_col', SqliteDataType.text)
          .notNull()
          .unique()
          .withDefaultValue('default_value');

      final sql = column.toSql();
      expect(sql, contains('test_col TEXT NOT NULL UNIQUE'));
      expect(sql, contains("DEFAULT 'default_value'"));
    });

    test('prevents duplicate table names in schema', () {
      expect(() {
        SchemaBuilder()
            .table('users', (table) => table.text('name'))
            .table('users', (table) => table.text('email'));
      }, throwsArgumentError);
    });

    test('prevents duplicate column names in table', () {
      expect(() {
        TableBuilder('test')
            .text('name')
            .text('name');
      }, throwsArgumentError);
    });
  });
}
