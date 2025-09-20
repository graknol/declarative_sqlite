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

### Step 2: Initialize Database

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // For standalone Dart apps

void main() async {
  // Initialize SQLite driver (for standalone Dart apps)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Create database instance
  final database = DeclarativeDatabase(
    schema: buildSchema,
    path: 'my_app.db',
  );

  // Schema is automatically created/migrated
  print('Database ready!');
}
```

### Step 3: Perform Basic Operations

```dart
// Insert data
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

// Query data
final users = await database.query('users');
print('Found ${users.length} users');

final posts = await database.query('posts', where: 'user_id = ?', whereArgs: ['user-1']);
print('User has ${posts.length} posts');

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
  print('Users table updated: ${users.length} total users');
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
    print('User updated: ${user['name']} (${user['age']} years old)');
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
        mapper: User.fromMap,
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
          trailing: Text('Age: ${user.age}'),
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
            Text('Email: ${user.email}'),
            Text('Age: ${user.age}'),
            Text('Created: ${user.createdAt.toString()}'),
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
      'id': 'user-${DateTime.now().millisecondsSinceEpoch}',
      'name': 'New User ${DateTime.now().second}',
      'email': 'user${DateTime.now().second}@example.com',
      'age': 25,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('User added!')),
    );
  }
}
```

### Step 3: Create Data Models

```dart
class User {
  final String id;
  final String name;
  final String email;
  final int age;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.age,
    required this.createdAt,
  });

  static User fromMap(Map<String, Object?> map) {
    return User(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      age: map['age'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'age': age,
      'created_at': createdAt.toIso8601String(),
    };
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