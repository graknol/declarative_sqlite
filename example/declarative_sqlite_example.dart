import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  // Example of declarative SQLite schema definition
  final schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('email', (col) => col.unique())
          .integer('age')
          .index('idx_email', ['email']))
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .text('content')
          .integer('user_id', (col) => col.notNull())
          .index('idx_user_id', ['user_id']));

  print('Generated SQL Schema:');
  print(schema.toSqlScript());
  
  print('\nTables: ${schema.tableNames.join(', ')}');
  print('Total tables: ${schema.tableCount}');
}
