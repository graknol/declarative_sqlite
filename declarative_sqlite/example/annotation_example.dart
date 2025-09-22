/// Example demonstrating the @GenerateDbRecord annotation approach
/// 
/// This example shows how to use class-level annotations
/// for generating typed record properties.

import 'package:declarative_sqlite/declarative_sqlite.dart';

// First, define your schema as usual
Schema createExampleSchema() {
  final builder = SchemaBuilder();
  
  builder.table('users', (table) {
    table.integer('id').notNull();
    table.text('name').notNull();
    table.text('email');
    table.integer('age');
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });
  
  builder.table('posts', (table) {
    table.integer('id').notNull();
    table.integer('user_id').notNull();
    table.text('title').notNull();
    table.text('content');
    table.date('published_at');
    table.key(['id']).primary();
  });
  
  return builder.build();
}

// Then, create annotated record classes that will have code generated for them

part 'annotation_example.g.dart'; // Generated code will go here

@GenerateDbRecord('users')
@RegisterFactory()
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);

  // This fromMap can now be a simple redirect to the generated factory
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return UserFactory.createFromMap(data, database);
  }
}

@GenerateDbRecord('posts')
@RegisterFactory()
class Post extends DbRecord {
  Post(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'posts', database);

  // This fromMap can now be a simple redirect to the generated factory
  static Post fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return PostFactory.createFromMap(data, database);
  }
}

// Example usage:
// 
// First, register all factories at app startup:
// registerAllFactories(database);
//
// Then use the typed properties:
// final user = User.fromMap(userData, database);
// print(user.name);      // Generated getter
// user.email = 'new@example.com';  // Generated setter
// await user.save();
//
// final post = Post.fromMap(postData, database);
// print(post.title);     // Generated getter (if title column exists)
// post.content = 'Updated content'; // Generated setter (if content column exists)
// await post.save();
//
// Automatic factory registration eliminates the need for manual setup:
// RecordMapFactoryRegistry.register<User>(User.fromMap);  // No longer needed!
// RecordMapFactoryRegistry.register<Post>(Post.fromMap);  // No longer needed!