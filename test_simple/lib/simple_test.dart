import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'simple_test.db.dart';

void defineTestSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id').notNull('');
    table.text('name').notNull('');
    table.integer('age').notNull(0);
    table.key(['id']).primary();
  });
}

@GenerateDbRecord('users')
class SimpleUser extends DbRecord {
  SimpleUser(Map<String, Object?> data, DeclarativeDatabase database) 
      : super(data, 'users', database);
}