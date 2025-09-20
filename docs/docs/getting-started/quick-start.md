---
sidebar_position: 2
---

# Quick Start

Get up and running with Declarative SQLite in just a few minutes! This guide will walk you through creating your first database schema and performing basic operations.

## Step 1: Create Your Schema

Let's start by defining a simple blog database with users and posts:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final blogSchema = SchemaBuilder()
  .table('users', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('username', (col) => col.notNull().unique())
    .text('email', (col) => col.notNull())
    .text('full_name')
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('last_login'))
  .table('posts', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('title', (col) => col.notNull())
    .text('content', (col) => col.notNull())
    .text('slug', (col) => col.notNull().unique())
    .integer('user_id', (col) => col.notNull())
    .boolean('published', (col) => col.notNull().defaultValue(false))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('published_at')
    .foreignKey('user_id').references('users', 'id'))
  .index('posts', ['user_id', 'published'])
  .index('posts', ['slug']);
```

## Step 2: Initialize the Database

```dart
Future<void> main() async {
  // Initialize the database
  final database = await DeclarativeDatabase.init(
    path: 'blog.db', // Use ':memory:' for in-memory database
    schema: blogSchema,
  );
  
  print('✅ Database initialized successfully!');
  
  // Database is ready to use
  await runExamples(database);
  
  // Don't forget to close when done
  await database.close();
}
```

## Step 3: Insert Data

```dart
Future<void> runExamples(DeclarativeDatabase database) async {
  // Insert a user
  final userId = await database.insert('users', {
    'username': 'johndoe',
    'email': 'john@example.com',
    'full_name': 'John Doe',
    'created_at': DateTime.now(),
  });
  
  print('Created user with ID: $userId');
  
  // Insert multiple posts
  final posts = [
    {
      'title': 'Getting Started with Dart',
      'content': 'Dart is a powerful programming language...',
      'slug': 'getting-started-dart',
      'user_id': userId,
      'published': true,
      'created_at': DateTime.now(),
      'published_at': DateTime.now(),
    },
    {
      'title': 'Building Mobile Apps',
      'content': 'Flutter makes mobile development easy...',
      'slug': 'building-mobile-apps',
      'user_id': userId,
      'published': false,
      'created_at': DateTime.now(),
    },
  ];
  
  for (final post in posts) {
    await database.insert('posts', post);
  }
  
  print('Created ${posts.length} posts');
}
```

## Step 4: Query Data

```dart
// Simple queries
final allUsers = await database.query('users');
print('Found ${allUsers.length} users');

final publishedPosts = await database.query('posts', 
  where: 'published = ?', 
  whereArgs: [1],
);
print('Found ${publishedPosts.length} published posts');

// Join queries
final postsWithAuthors = await database.rawQuery('''
  SELECT 
    p.title,
    p.content,
    p.published_at,
    u.username,
    u.full_name
  FROM posts p
  JOIN users u ON p.user_id = u.id
  WHERE p.published = 1
  ORDER BY p.published_at DESC
''');

for (final post in postsWithAuthors) {
  print('${post['title']} by ${post['full_name']}');
}
```

## Step 5: Real-time Streaming (Optional)

One of the powerful features of Declarative SQLite is real-time data streaming:

```dart
// Listen to all published posts
final publishedPostsStream = database
  .from('posts')
  .where((row) => row['published'] == true)
  .stream();

publishedPostsStream.listen((posts) {
  print('Published posts updated: ${posts.length} posts');
});

// Insert a new post - the stream will automatically update
await database.insert('posts', {
  'title': 'Real-time Updates',
  'content': 'This post will trigger the stream!',
  'slug': 'real-time-updates',
  'user_id': userId,
  'published': true,
  'created_at': DateTime.now(),
  'published_at': DateTime.now(),
});
```

## Complete Example

Here's the complete working example:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final blogSchema = SchemaBuilder()
  .table('users', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('username', (col) => col.notNull().unique())
    .text('email', (col) => col.notNull())
    .text('full_name')
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now())))
  .table('posts', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('title', (col) => col.notNull())
    .text('content', (col) => col.notNull())
    .text('slug', (col) => col.notNull().unique())
    .integer('user_id', (col) => col.notNull())
    .boolean('published', (col) => col.notNull().defaultValue(false))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('published_at')
    .foreignKey('user_id').references('users', 'id'));

Future<void> main() async {
  final database = await DeclarativeDatabase.init(
    path: ':memory:',
    schema: blogSchema,
  );
  
  // Insert sample data
  final userId = await database.insert('users', {
    'username': 'johndoe',
    'email': 'john@example.com',
    'full_name': 'John Doe',
  });
  
  await database.insert('posts', {
    'title': 'My First Post',
    'content': 'Hello, world!',
    'slug': 'my-first-post',
    'user_id': userId,
    'published': true,
    'published_at': DateTime.now(),
  });
  
  // Query data
  final posts = await database.query('posts');
  print('Created ${posts.length} posts');
  
  await database.close();
}
```

## What's Next?

Now that you've created your first Declarative SQLite database, you can explore:

- **[Schema Definition](../core-library/schema-definition)** - Learn about advanced schema features
- **[Database Operations](../core-library/database-operations)** - Master CRUD operations and queries
- **[Streaming Queries](../core-library/streaming-queries)** - Build reactive applications
- **[Code Generation](https://pub.dev/packages/declarative_sqlite_generator)** - Generate type-safe data classes
- **[Flutter Integration](../flutter/installation)** - Build Flutter apps with reactive widgets

## Need Help?

- Check out more [examples](./examples)
- Read the [API Reference](#api-reference) (coming soon)
- See the [troubleshooting guide](#troubleshooting) (coming soon)