# Database Operations

Learn how to perform CRUD operations, queries, and transactions with Declarative SQLite.

## Database Instance

The `DeclarativeDatabase` class is your main interface for database operations:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final database = DeclarativeDatabase(
  schema: buildSchema,
  path: 'my_app.db',
);
```

## Basic CRUD Operations

### Working with Typed Records

The modern approach using typed records (recommended):

```dart
// Register your record types first (usually in main())
RecordMapFactoryRegistry.register<User>(User.fromMap);

// Create a new user
final newUser = User.create(database);
newUser.name = 'John Doe';
newUser.email = 'john@example.com';
newUser.age = 30;
await newUser.save(); // Automatically handles INSERT

// Query users with type safety
final users = await database.queryTyped<User>((q) => q.from('users'));
for (final user in users) {
  print('User: ${user.name} (${user.email})'); // Type-safe property access
}

// Update a user
final user = users.first;
user.email = 'newemail@example.com';
user.age = 31;
await user.save(); // Automatically handles UPDATE (only modified fields)

// Delete a user
await user.delete();
```

### Raw Map Operations

For cases where you need direct control or don't have typed records:

### Insert Data

```dart
// Insert a single record
await database.insert('users', {
  'id': 'user-1',
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30,
  'created_at': DateTime.now().toIso8601String(),
});

// Insert multiple records efficiently
await database.insertAll('users', [
  {
    'id': 'user-2',
    'name': 'Jane Smith',
    'email': 'jane@example.com',
    'age': 25,
    'created_at': DateTime.now().toIso8601String(),
  },
  {
    'id': 'user-3',
    'name': 'Bob Johnson',
    'email': 'bob@example.com',
    'age': 35,
    'created_at': DateTime.now().toIso8601String(),
  },
]);
```

### Query Data

With typed records (recommended):

```dart
// Query all users with type safety
final allUsers = await database.queryTyped<User>((q) => q.from('users'));

// Query with WHERE conditions
final adultUsers = await database.queryTyped<User>((q) => 
  q.from('users').where('age >= ?', [18])
);

// Query with ordering and limits
final recentUsers = await database.queryTyped<User>((q) => 
  q.from('users')
   .orderBy('created_at DESC')
   .limit(10)
);

// Complex queries with joins
final usersWithPosts = await database.queryTyped<User>((q) =>
  q.from('users u')
   .join('posts p', 'p.user_id = u.id')
   .where('p.created_at > ?', [DateTime.now().subtract(Duration(days: 7))])
   .groupBy('u.id')
   .forUpdate('users') // Enable CRUD operations
);

// Table-specific queries (automatically CRUD-enabled)
final activeUsers = await database.queryTableTyped<User>('users',
  where: 'active = ?',
  whereArgs: [true],
  orderBy: 'name ASC',
);
```

With raw maps:

```dart
// Query all records
final allUsers = await database.query('users');

// Query with WHERE clause
final adultUsers = await database.query(
  'users',
  where: 'age >= ?',
  whereArgs: [18],
);

// Query with ordering
final usersByName = await database.query(
  'users',
  orderBy: 'name ASC',
);

// Query with limits
final recentUsers = await database.query(
  'users',
  orderBy: 'created_at DESC',
  limit: 10,
);

// Query specific columns
final userNames = await database.query(
  'users',
  columns: ['id', 'name'],
);

// Complex query with multiple conditions
final filteredUsers = await database.query(
  'users',
  where: 'age BETWEEN ? AND ? AND email LIKE ?',
  whereArgs: [25, 40, '%@example.com'],
  orderBy: 'name ASC',
  limit: 5,
  offset: 10,
);
```

### Update Data

```dart
// Update single record
await database.update(
  'users',
  {'age': 31},
  where: 'id = ?',
  whereArgs: ['user-1'],
);

// Update multiple records
await database.update(
  'users',
  {'updated_at': DateTime.now().toIso8601String()},
  where: 'age < ?',
  whereArgs: [18],
);

// Conditional update
final updatedCount = await database.update(
  'users',
  {'status': 'verified'},
  where: 'email IS NOT NULL AND status = ?',
  whereArgs: ['pending'],
);
print('Updated $updatedCount users');
```

### Delete Data

```dart
// Delete single record
await database.delete(
  'users',
  where: 'id = ?',
  whereArgs: ['user-1'],
);

// Delete multiple records
await database.delete(
  'users',
  where: 'age < ?',
  whereArgs: [13],
);

// Delete all records (use with caution!)
await database.delete('users');

// Get count of deleted records
final deletedCount = await database.delete(
  'users',
  where: 'last_login < ?',
  whereArgs: [DateTime.now().subtract(Duration(days: 365)).toIso8601String()],
);
print('Deleted $deletedCount inactive users');
```

## Advanced Queries

### Joins and Complex Queries

For complex queries, use raw SQL with proper parameter binding:

```dart
// Join queries
final userPosts = await database.rawQuery('''
  SELECT users.name, posts.title, posts.created_at
  FROM users
  JOIN posts ON users.id = posts.user_id
  WHERE users.id = ?
  ORDER BY posts.created_at DESC
''', ['user-1']);

// Aggregate queries
final userStats = await database.rawQuery('''
  SELECT 
    users.id,
    users.name,
    COUNT(posts.id) as post_count,
    MAX(posts.created_at) as latest_post
  FROM users
  LEFT JOIN posts ON users.id = posts.user_id
  GROUP BY users.id, users.name
  HAVING post_count > ?
''', [0]);

// Subqueries
final activeUsers = await database.rawQuery('''
  SELECT * FROM users
  WHERE id IN (
    SELECT DISTINCT user_id 
    FROM posts 
    WHERE created_at > ?
  )
''', [DateTime.now().subtract(Duration(days: 30)).toIso8601String()]);
```

### Working with Views

Query views just like tables:

```dart
// Assuming you have defined a view in your schema
final publishedPosts = await database.query('published_posts');

final postSummaries = await database.query(
  'post_summaries',
  where: 'author_name LIKE ?',
  whereArgs: ['%John%'],
);
```

## Transactions

Use transactions for atomic operations:

### Basic Transactions

```dart
await database.transaction((txn) async {
  // All operations in this block are atomic
  await txn.insert('users', {
    'id': 'user-4',
    'name': 'Alice Brown',
    'email': 'alice@example.com',
    'age': 28,
    'created_at': DateTime.now().toIso8601String(),
  });

  await txn.insert('posts', {
    'id': 'post-1',
    'user_id': 'user-4',
    'title': 'My First Post',
    'content': 'Hello, world!',
    'created_at': DateTime.now().toIso8601String(),
  });

  // If any operation fails, all changes are rolled back
});
```

### Error Handling in Transactions

```dart
try {
  await database.transaction((txn) async {
    await txn.insert('orders', orderData);
    
    for (final item in orderItems) {
      await txn.insert('order_items', item);
      
      // Update inventory
      final product = await txn.query(
        'products', 
        where: 'id = ?', 
        whereArgs: [item['product_id']],
      );
      
      if (product.isEmpty) {
        throw Exception('Product not found: ${item['product_id']}');
      }
      
      final currentStock = product.first['stock_quantity'] as int;
      final newStock = currentStock - (item['quantity'] as int);
      
      if (newStock < 0) {
        throw Exception('Insufficient stock for product: ${item['product_id']}');
      }
      
      await txn.update(
        'products',
        {'stock_quantity': newStock},
        where: 'id = ?',
        whereArgs: [item['product_id']],
      );
    }
  });
  
  print('Order processed successfully');
} catch (e) {
  print('Order failed: $e');
  // Transaction was automatically rolled back
}
```

## Batch Operations

For better performance with multiple operations:

```dart
// Batch insert
final batch = database.batch();

for (int i = 0; i < 1000; i++) {
  batch.insert('users', {
    'id': 'user-$i',
    'name': 'User $i',
    'email': 'user$i@example.com',
    'age': 20 + (i % 50),
    'created_at': DateTime.now().toIso8601String(),
  });
}

// Execute all operations at once
await batch.commit();

// Batch with mixed operations
final mixedBatch = database.batch();

mixedBatch.insert('users', userData);
mixedBatch.update('posts', postUpdate, where: 'user_id = ?', whereArgs: [userId]);
mixedBatch.delete('comments', where: 'post_id = ?', whereArgs: [postId]);

await mixedBatch.commit();
```

## Data Type Handling

### DateTime Handling

```dart
// Insert with DateTime
await database.insert('events', {
  'id': 'event-1',
  'name': 'Meeting',
  'start_time': DateTime.now().toIso8601String(),
  'end_time': DateTime.now().add(Duration(hours: 1)).toIso8601String(),
});

// Query and parse DateTime
final events = await database.query('events');
for (final event in events) {
  final startTime = DateTime.parse(event['start_time'] as String);
  final endTime = DateTime.parse(event['end_time'] as String);
  print('Event: ${event['name']} from $startTime to $endTime');
}

// Query with date comparisons
final upcomingEvents = await database.query(
  'events',
  where: 'start_time > ?',
  whereArgs: [DateTime.now().toIso8601String()],
);
```

### Null Handling

```dart
// Insert with null values
await database.insert('users', {
  'id': 'user-5',
  'name': 'John',
  'email': 'john@example.com',
  'phone': null, // Optional field
});

// Query with null checks
final usersWithoutPhone = await database.query(
  'users',
  where: 'phone IS NULL',
);

final usersWithPhone = await database.query(
  'users',
  where: 'phone IS NOT NULL',
);
```

### JSON Data

While SQLite doesn't have native JSON support, you can store JSON as text:

```dart
import 'dart:convert';

// Store JSON data
final userData = {
  'id': 'user-6',
  'name': 'Jane',
  'preferences': jsonEncode({
    'theme': 'dark',
    'notifications': true,
    'language': 'en',
  }),
};

await database.insert('users', userData);

// Retrieve and parse JSON
final users = await database.query('users', where: 'id = ?', whereArgs: ['user-6']);
if (users.isNotEmpty) {
  final user = users.first;
  final preferences = jsonDecode(user['preferences'] as String);
  print('User theme: ${preferences['theme']}');
}
```

## Performance Optimization

### Indexing

While Declarative SQLite doesn't currently provide explicit index definition in the schema builder, you can create indexes manually:

```dart
// Create indexes for better query performance
await database.execute('CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)');
await database.execute('CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)');
await database.execute('CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at)');
```

### Query Optimization Tips

```dart
// Use specific columns instead of SELECT *
final userEmails = await database.query('users', columns: ['email']);

// Use LIMIT for pagination
final pagedUsers = await database.query(
  'users',
  orderBy: 'created_at DESC',
  limit: 20,
  offset: page * 20,
);

// Use WHERE clauses to reduce result sets
final recentPosts = await database.query(
  'posts',
  where: 'created_at > ?',
  whereArgs: [DateTime.now().subtract(Duration(days: 7)).toIso8601String()],
);
```

### Memory Management

```dart
// For large result sets, consider streaming
final Stream<Map<String, Object?>> userStream = database.streamQuery('users');
await for (final users in userStream) {
  // Process users in chunks as they arrive
  for (final user in users) {
    await processUser(user);
  }
}

// Close database when done
await database.close();
```

## Error Handling

```dart
try {
  await database.insert('users', userData);
} on DatabaseException catch (e) {
  if (e.isUniqueConstraintError()) {
    print('User already exists');
  } else if (e.isNotNullConstraintError()) {
    print('Required field is missing');
  } else {
    print('Database error: ${e.message}');
  }
} catch (e) {
  print('Unexpected error: $e');
}

// Graceful error handling for queries
Future<List<Map<String, Object?>>> safeQuery(String table) async {
  try {
    return await database.query(table);
  } catch (e) {
    print('Query failed for table $table: $e');
    return [];
  }
}
```

## Database Lifecycle

```dart
class DatabaseManager {
  DeclarativeDatabase? _database;

  Future<DeclarativeDatabase> get database async {
    if (_database == null) {
      _database = DeclarativeDatabase(
        schema: buildSchema,
        path: 'app.db',
      );
    }
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

// Use in your app
final dbManager = DatabaseManager();
final db = await dbManager.database;

// Perform operations
await db.insert('users', userData);

// Clean up when app closes
await dbManager.close();
```

## Best Practices

### Parameter Binding

Always use parameter binding to prevent SQL injection:

```dart
// ✅ Good - Uses parameter binding
final users = await database.query(
  'users',
  where: 'name = ? AND age > ?',
  whereArgs: [userName, minAge],
);

// ❌ Bad - Vulnerable to SQL injection
final users = await database.rawQuery(
  "SELECT * FROM users WHERE name = '$userName' AND age > $minAge"
);
```

### Data Validation

```dart
Future<void> insertUser(Map<String, Object?> userData) async {
  // Validate data before insertion
  if (userData['email'] == null || (userData['email'] as String).isEmpty) {
    throw ArgumentError('Email is required');
  }
  
  if (userData['age'] != null && (userData['age'] as int) < 0) {
    throw ArgumentError('Age must be positive');
  }
  
  await database.insert('users', userData);
}
```

### Connection Management

```dart
// Use a singleton pattern for database access
class DatabaseService {
  static DeclarativeDatabase? _instance;
  
  static Future<DeclarativeDatabase> get instance async {
    _instance ??= DeclarativeDatabase(
      schema: buildSchema,
      path: 'app.db',
    );
    return _instance!;
  }
}

// Usage
final db = await DatabaseService.instance;
await db.insert('users', userData);
```

## Next Steps

Now that you understand database operations, explore:

- [Typed Records](typed-records) - Work with typed record classes instead of raw maps
- [Exception Handling](exception-handling) - Handle database errors gracefully
- [Advanced Features](advanced-features) - Garbage collection and other utilities
- [Streaming Queries](streaming-queries) - Real-time data updates