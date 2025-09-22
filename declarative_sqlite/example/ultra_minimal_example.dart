/// Ultra-Minimal Example: The Future of Declarative SQLite
/// 
/// This example shows the absolute minimum code that developers
/// need to write with the enhanced code generation.

import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'ultra_minimal_example.g.dart'; // Generated code will go here

// Schema definition (could even be generated from database in the future!)
Schema createSchema() {
  return SchemaBuilder()
    ..table('users', (table) {
      table.integer('id').notNull();
      table.text('name').notNull();
      table.text('email');
      table.integer('age');
      table.date('created_at').notNull();
      table.key(['id']).primary();
    })
    ..table('posts', (table) {
      table.integer('id').notNull();
      table.integer('user_id').notNull();
      table.text('title').notNull();
      table.text('content');
      table.date('published_at');
      table.key(['id']).primary();
    })
    ..build();
}

// ============================================================================
// THIS IS ALL THE DEVELOPER WRITES! (Just the class definition!)
// Everything else is generated automatically.
// ============================================================================

@GenerateDbRecord('users')
@RegisterFactory()
class User extends DbRecord with UserFromMapMixin {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);
  
  // fromMap is provided by the generated mixin!
  // No need to write it manually anymore!
}

@GenerateDbRecord('posts')  
@RegisterFactory()
class Post extends DbRecord with PostFromMapMixin {
  Post(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'posts', database);
  
  // fromMap is provided by the generated mixin!
  // No need to write it manually anymore!
}

// ============================================================================
// Usage example - This is how easy it becomes
// ============================================================================

void demonstrateUltraMinimalUsage() async {
  // Open database
  final database = await DeclarativeDatabase.open('ultra_minimal.db', schema: createSchema());
  
  // One line to register ALL factories automatically!
  registerAllFactories(database);
  
  // Create records with zero boilerplate
  final userData = {
    'id': 1,
    'name': 'Alice Smith',
    'email': 'alice@example.com',
    'age': 28,
    'created_at': DateTime.now().toIso8601String(),
  };
  
  // The fromMap is generated and available via mixin!
  final user = UserFromMapMixin.fromMap(userData, database);
  
  // All properties are generated with full type safety
  print('User: ${user.name} (${user.age})');  // Generated getters
  user.email = 'alice.smith@newcompany.com'; // Generated setter
  
  await user.save();
  
  // Typed queries work automatically (no mappers needed)
  final users = await database.queryTyped<User>((q) => q.from('users'));
  for (final user in users) {
    print('${user.name}: ${user.email}');
  }
  
  // Or even simpler table queries
  final allUsers = await database.queryTableTyped<User>('users');
  print('Found ${allUsers.length} users');
}

// ============================================================================
// What the generator produces (for reference - this is all automatic):
// ============================================================================

/* Generated code (automatic):

// Typed properties
extension UserGenerated on User {
  int get id => getIntegerNotNull('id');
  String get name => getTextNotNull('name');
  String? get email => getText('email');
  int? get age => getInteger('age');
  DateTime get createdAt => getDateTimeNotNull('created_at');
  
  set name(String value) => setText('name', value);
  set email(String? value) => setText('email', value);
  set age(int? value) => setInteger('age', value);
  set createdAt(DateTime value) => setDateTime('created_at', value);
}

// Factory methods
extension UserFactory on User {
  static User createFromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
  
  static User Function(Map<String, Object?>) getFactory(DeclarativeDatabase database) {
    return (data) => createFromMap(data, database);
  }
}

// FromMap mixin
mixin UserFromMapMixin {
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return UserFactory.createFromMap(data, database);
  }
}

// Registration functions
void registerAllFactories(DeclarativeDatabase database) {
  RecordMapFactoryRegistry.register<User>(UserFactory.getFactory(database));
  RecordMapFactoryRegistry.register<Post>(PostFactory.getFactory(database));
}

*/