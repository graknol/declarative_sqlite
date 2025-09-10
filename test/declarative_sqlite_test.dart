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

    test('can create schema with views', () {
      final schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('username', (col) => col.notNull())
              .text('email', (col) => col.unique())
              .integer('active', (col) => col.withDefaultValue(1)))
          .addView(ViewBuilder.simple('active_users', 'users', 'active = 1'))
          .view('user_summary', (name) => ViewBuilder.withColumns(name, 'users', ['id', 'username', 'email']));

      expect(schema.tableCount, equals(1));
      expect(schema.viewCount, equals(2));
      expect(schema.totalCount, equals(3));
      expect(schema.hasTable('users'), isTrue);
      expect(schema.hasView('active_users'), isTrue);
      expect(schema.hasView('user_summary'), isTrue);
      expect(schema.viewNames, containsAll(['active_users', 'user_summary']));
      expect(schema.allNames, containsAll(['users', 'active_users', 'user_summary']));
    });

    test('can generate SQL for schema with views', () {
      final schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull()))
          .addView(ViewBuilder.simple('all_users', 'users'));

      final statements = schema.toSqlStatements();
      expect(statements.length, greaterThan(1));
      
      // Should have CREATE TABLE statement
      expect(statements.any((stmt) => stmt.contains('CREATE TABLE users')), isTrue);
      // Should have CREATE VIEW statement
      expect(statements.any((stmt) => stmt.contains('CREATE VIEW all_users AS')), isTrue);
      
      // Views should come after tables in the statements
      final tableIndex = statements.indexWhere((stmt) => stmt.contains('CREATE TABLE'));
      final viewIndex = statements.indexWhere((stmt) => stmt.contains('CREATE VIEW'));
      expect(tableIndex, lessThan(viewIndex));
    });

    test('prevents duplicate view names', () {
      expect(() {
        SchemaBuilder()
            .addView(ViewBuilder.simple('duplicate', 'users'))
            .addView(ViewBuilder.simple('duplicate', 'posts'));
      }, throwsArgumentError);
    });

    test('prevents view names conflicting with table names', () {
      expect(() {
        SchemaBuilder()
            .table('users', (table) => table.text('name'))
            .addView(ViewBuilder.simple('users', 'posts'));
      }, throwsArgumentError);
    });

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
