import 'package:declarative_sqlite/declarative_sqlite.dart';

void defineSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id');
    table.text('name').notNull();
    table.integer('age');
  });
}
