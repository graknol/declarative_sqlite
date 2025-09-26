import 'package:declarative_sqlite/declarative_sqlite.dart';

@DbSchema()
void defineSchema22(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id').notNull('');
    table.text('name').notNull('');
    table.text('email').notNull('');
    table.integer('age').notNull(0);
    table.key(['id']).primary();
  });

  builder.table('posts', (table) {
    table.guid('id').notNull('');
    table.guid('user_id').notNull('');
    table.text('title').notNull('');
    table.text('content').notNull('');
    table.key(['id']).primary();
  });
}