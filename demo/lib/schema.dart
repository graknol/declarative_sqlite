
import 'package:declarative_sqlite/declarative_sqlite.dart';

@DbSchema()
void buildDatabaseSchema(SchemaBuilder builder) {
  // Users table
  builder.table('users', (table) {
    table.guid('id').notNull('');
    table.text('name').notNull('').lww(); // LWW column for sync
    table.text('email').notNull('').lww(); // LWW column for sync
    table.integer('age').notNull(0).lww(); // LWW column for sync
    table.text('gender').notNull('non-binary').lww(); // LWW column for sync
    table.integer('kids').notNull(0).lww(); // LWW column for sync
    table.date('created_at').notNull().defaultCallback(() => DateTime.now());
    table.key(['id']).primary();
  });

  // Posts table
  builder.table('posts', (table) {
    table.guid('id').notNull('');
    table.guid('user_id').notNull('');
    table.text('title').notNull('').lww(); // LWW column for sync
    table.text('content').notNull('').lww(); // LWW column for sync
    table.date('created_at').notNull().defaultCallback(() => DateTime.now());
    table.text('user_name').notNull(''); // Denormalized for demo simplicity
    table.key(['id']).primary();
  });
}
