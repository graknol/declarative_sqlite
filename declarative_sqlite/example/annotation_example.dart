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
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);

  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
}

@GenerateDbRecord('posts')
class Post extends DbRecord {
  Post(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'posts', database);

  static Post fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return Post(data, database);
  }
}

// Example usage:
// 
// final user = User.fromMap(userData, database);
// print(user.name);      // Generated getter
// user.email = 'new@example.com';  // Generated setter
// await user.save();
//
// final post = Post.fromMap(postData, database);
// print(post.title);     // Generated getter
// post.content = 'Updated content'; // Generated setter
// await post.save();