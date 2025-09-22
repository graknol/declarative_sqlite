/// Minimal Example demonstrating how little code developers need to write
/// 
/// This example shows the absolute minimum boilerplate needed when using
/// the enhanced code generation features.

import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'minimal_example.g.dart'; // Generated code will go here

// Schema definition (this would typically be in a separate file)
Schema createMinimalSchema() {
  final builder = SchemaBuilder();
  
  builder.table('users', (table) {
    table.integer('id').notNull();
    table.text('name').notNull();
    table.text('email');
    table.integer('age');
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });
  
  return builder.build();
}

// THIS IS ALL THE DEVELOPER NEEDS TO WRITE!
// The generator will create all getters, setters, and factory methods

@GenerateDbRecord('users')
@RegisterFactory()
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);

  // Even this fromMap method can be optional if you only use automatic registration!
  // For direct usage: UserGenerated.fromMap(data, database)
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return UserGenerated.fromMap(data, database);
  }
}

// Usage example:
void exampleUsage() async {
  // Open database
  final database = await DeclarativeDatabase.open('example.db', schema: createMinimalSchema());
  
  // Register all factories automatically!
  registerAllFactories(database);
  
  // Create and use records with full type safety
  final userData = {
    'id': 1,
    'name': 'John Doe',
    'email': 'john@example.com',
    'age': 30,
    'created_at': DateTime.now().toIso8601String(),
  };
  
  final user = User.fromMap(userData, database);
  
  // Or use the generated extension directly:
  // final user = UserGenerated.fromMap(userData, database);
  
  // Use generated getters and setters
  print('User: ${user.name} (${user.age})');  // Generated getters!
  user.email = 'john.doe@newcompany.com';    // Generated setter!
  
  await user.save();
  
  // Or use with typed queries (no manual mappers needed!)
  final users = await database.queryTyped<User>((q) => q.from('users'));
  for (final user in users) {
    print('${user.name}: ${user.email}');
  }
}