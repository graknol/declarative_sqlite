# Quick Start

This guide will walk you through creating your first Declarative SQLite application in just a few minutes.

## Core Library Quick Start

### Step 1: Define Your Schema

Start by defining your database schema using the fluent builder API:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

void buildSchema(SchemaBuilder builder) {
  // Define a users table
  builder.table('users', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.text('email').notNull();
    table.integer('age').min(0);
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });

  // Define a posts table
  builder.table('posts', (table) {
    table.guid('id').notNull();
    table.guid('user_id').notNull();
    table.text('title').notNull();
    table.text('content');
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });
}
```

### Step 2: Create Typed Record Classes (Optional but Recommended)

For the best developer experience, create typed record classes:

```dart
// lib/models/user.dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'user.g.dart'; // Generated code will be here

@GenerateDbRecord('users')
@RegisterFactory()
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);

  // Optional: redirect to generated extension
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return UserGenerated.fromMap(data, database);
  }
}

// lib/models/post.dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'post.g.dart';

@GenerateDbRecord('posts')
@RegisterFactory()
class Post extends DbRecord {
  Post(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'posts', database);

  // Optional: redirect to generated extension
  static Post fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return PostGenerated.fromMap(data, database);
  }
}
```

Add the generator to your `pubspec.yaml`:

```yaml
dev_dependencies:
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.0
```

Run code generation:

```bash
dart run build_runner build
```

### Step 3: Initialize Database with Typed Records

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // For standalone Dart apps
import 'models/user.dart';
import 'models/post.dart';

void main() async {
  // Initialize SQLite driver (for standalone Dart apps)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Create database instance
  final database = DeclarativeDatabase(
    schema: buildSchema,
    path: 'my_app.db',
  );

  // Register all typed record factories automatically!
  registerAllFactories(database);

  // Schema is automatically created/migrated
  print('Database ready!');
}
```

### Step 4: Perform Operations with Typed Records

With typed records (recommended approach):

```dart
// Create and save a new user
final newUser = User.create(database);
newUser.name = 'John Doe';
newUser.email = 'john@example.com';
newUser.age = 30;
newUser.createdAt = DateTime.now();
await newUser.save();

// Create a post
final newPost = Post.create(database);
newPost.userId = newUser.id;
newPost.title = 'My First Post';
newPost.content = 'Hello, world!';
newPost.createdAt = DateTime.now();
await newPost.save();

// Query with type safety
final users = await database.queryTyped<User>((q) => q.from('users'));
print('Found ${'${users.length}'} users');

final user = users.first;
print('User: ${'${user.name}'} (${'${user.email}'})'); // Type-safe property access

// Update with type safety
user.email = 'newemail@example.com';
await user.save(); // Only modified fields are updated

// Query posts for a user
final userPosts = await database.queryTyped<Post>((q) => 
  q.from('posts').where('user_id = ?', [user.id])
);
print('User has ${'${userPosts.length}'} posts');
```

### Alternative: Raw Map Operations

You can also work with raw maps if needed:

```dart
// Insert data using raw maps
await database.insert('users', {
  'id': 'user-1',
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30,
  'created_at': DateTime.now().toIso8601String(),
});

await database.insert('posts', {
  'id': 'post-1',
  'user_id': 'user-1',
  'title': 'My First Post',
  'content': 'Hello, world!',
  'created_at': DateTime.now().toIso8601String(),
});

// Query data using raw maps
final users = await database.query('users');
print('Found ${'${users.length}'} users');

for (final user in users) {
  final userName = user['name'] as String;
  final userEmail = user['email'] as String;
  print('User: $userName ($userEmail)');
}

// Query related data
final posts = await database.query('posts', where: 'user_id = ?', whereArgs: ['user-1']);
print('User has ${'${posts.length}'} posts');

// Update data
await database.update(
  'users',
  {'age': 31},
  where: 'id = ?',
  whereArgs: ['user-1'],
);

// Delete data
await database.delete('posts', where: 'id = ?', whereArgs: ['post-1']);
```

### Step 4: Use Streaming Queries

```dart
// Listen to real-time updates
final userStream = database.streamQuery('users');
userStream.listen((users) {
  print('Users table updated: ${'${users.length}'} total users');
});

// Listen to specific user changes
final specificUserStream = database.streamQuery(
  'users',
  where: 'id = ?',
  whereArgs: ['user-1'],
);
specificUserStream.listen((users) {
  if (users.isNotEmpty) {
    final user = users.first;
    print('User updated: ${'${user[\'name\']}'} (${'${user[\'age\']}'} years old)');
  }
});

// Make changes - streams will automatically update
await database.insert('users', {
  'id': 'user-2',
  'name': 'Jane Smith',
  'email': 'jane@example.com',
  'age': 25,
  'created_at': DateTime.now().toIso8601String(),
});
```

## Flutter Integration Quick Start

### Step 1: Setup DatabaseProvider

```dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Declarative SQLite Demo',
      home: DatabaseProvider(
        schema: buildSchema, // Use the same schema from above
        databaseName: 'flutter_app.db',
        onDatabaseReady: (database) {
          // Register all typed record factories automatically!
          registerAllFactories(database);
        },
        child: UserListScreen(),
      ),
    );
  }
}
```

### Step 2: Create Reactive UI

```dart
class UserListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Users')),
      body: QueryListView<User>(
        database: DatabaseProvider.of(context),
        query: (q) => q.from('users').orderBy('name'),
        // No mapper needed - uses automatic factory registry
        loadingBuilder: (context) => Center(
          child: CircularProgressIndicator(),
        ),
        errorBuilder: (context, error) => Center(
          child: Text('Error: $error'),
        ),
        itemBuilder: (context, user) => ListTile(
          leading: CircleAvatar(child: Text(user.name[0])),
          title: Text(user.name),
          subtitle: Text(user.email),
          trailing: Text('Age: ${'${user.age}'}'),
          onTap: () => _showUserDetails(context, user),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addUser(context),
        child: Icon(Icons.add),
      ),
    );
  }
  
  void _showUserDetails(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: ${'${user.email}'}'),
            Text('Age: ${'${user.age}'}'),
            Text('Created: ${'${user.createdAt.toString()}'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _addUser(BuildContext context) async {
    final db = DatabaseProvider.of(context);
    await db.insert('users', {
      'id': 'user-${'${DateTime.now().millisecondsSinceEpoch}'}',
      'name': 'New User ${'${DateTime.now().second}'}',
      'email': 'user${'${DateTime.now().second}'}@example.com',
      'age': 25,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('User added!')),
    );
  }
}
```

## What's Next?

Congratulations! You now have a working Declarative SQLite application. Here are some next steps:

1. **Learn more about [Schema Definition](../core-library/schema-definition)** - Explore advanced column types, constraints, and relationships
2. **Dive into [Database Operations](../core-library/database-operations)** - Master querying, transactions, and performance optimization
3. **Explore [Flutter Integration](../flutter-integration/widgets)** - Discover more reactive widgets and patterns

## Complete Example

You can find complete working examples in the repository:

- **Core Library Example**: [`declarative_sqlite/example/`](https://github.com/graknol/declarative_sqlite/tree/main/declarative_sqlite/example)
- **Flutter Example**: [`declarative_sqlite_flutter/example/`](https://github.com/graknol/declarative_sqlite/tree/main/declarative_sqlite_flutter/example)