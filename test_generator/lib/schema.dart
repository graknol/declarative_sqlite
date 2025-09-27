import 'package:declarative_sqlite/declarative_sqlite.dart';

@DbSchema()
void defineSchema22(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id').notNull('');
    table.text('name').notNull('').lww(); // LWW column
    table.text('email').notNull(''); // Non-LWW column
    table.integer('age').notNull(0); // Non-LWW column
    table.key(['id']).primary();
  });

  builder.table('posts', (table) {
    table.guid('id').notNull('');
    table.guid('user_id').notNull('');
    table.text('title').notNull('').lww(); // LWW column
    table.text('content').notNull(''); // Non-LWW column
    table.key(['id']).primary();
  });
}