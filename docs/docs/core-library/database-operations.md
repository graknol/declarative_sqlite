---
sidebar_position: 3
---

# Database Operations

Master the core database operations in Declarative SQLite, from basic CRUD operations to advanced querying and streaming.

## Database Initialization

### Basic Initialization

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final database = await DeclarativeDatabase.init(
  path: 'my_app.db',
  schema: mySchema,
);
```

### Advanced Configuration

```dart
final database = await DeclarativeDatabase.init(
  path: 'my_app.db',
  schema: mySchema,
  options: DatabaseOptions(
    logQueries: true,              // Log all SQL queries
    logMigrations: true,           // Log migration steps
    enableForeignKeys: true,       // Enable foreign key constraints
    busyTimeout: Duration(seconds: 30),
    pageSize: 4096,               // SQLite page size
  ),
  migrationOptions: MigrationOptions(
    validateSchema: true,          // Validate before applying
    dryRun: false,                // Set true to preview changes
    onMigrationStart: (from, to) => print('Migrating from v$from to v$to'),
    onMigrationComplete: (from, to) => print('Migration complete'),
  ),
);
```

## CRUD Operations

### Insert Operations

#### Single Insert

```dart
// Insert a single record
final userId = await database.insert('users', {
  'username': 'johndoe',
  'email': 'john@example.com',
  'full_name': 'John Doe',
  'created_at': DateTime.now(),
});

print('Created user with ID: $userId');
```

#### Batch Insert

```dart
// Insert multiple records efficiently
final users = [
  {'username': 'alice', 'email': 'alice@example.com'},
  {'username': 'bob', 'email': 'bob@example.com'},
  {'username': 'charlie', 'email': 'charlie@example.com'},
];

await database.batch((batch) {
  for (final user in users) {
    batch.insert('users', user);
  }
});
```

#### Insert with Generated Data Classes

```dart
// When using code generation
final user = UsersData(
  username: 'johndoe',
  email: 'john@example.com',
  fullName: 'John Doe',
  createdAt: DateTime.now(),
);

final userId = await database.insertData(user);
```

### Query Operations

#### Basic Queries

```dart
// Get all records
final allUsers = await database.query('users');

// Query with conditions
final activeUsers = await database.query(
  'users',
  where: 'is_active = ?',
  whereArgs: [true],
  orderBy: 'created_at DESC',
  limit: 10,
);

// Query single record
final user = await database.queryFirst(
  'users',
  where: 'id = ?',
  whereArgs: [userId],
);
```

#### Advanced Queries

```dart
// Complex WHERE conditions
final recentActiveUsers = await database.query(
  'users',
  where: 'is_active = ? AND created_at > ? AND last_login IS NOT NULL',
  whereArgs: [true, DateTime.now().subtract(Duration(days: 30))],
  orderBy: 'last_login DESC',
);

// Query with joins
final postsWithAuthors = await database.rawQuery('''
  SELECT 
    p.id,
    p.title,
    p.content,
    p.created_at,
    u.username,
    u.full_name
  FROM posts p
  INNER JOIN users u ON p.user_id = u.id
  WHERE p.published = 1
  ORDER BY p.created_at DESC
  LIMIT 20
''');
```

#### Query Builder Pattern

```dart
// Using the fluent query builder
final posts = await database
  .from('posts')
  .select(['id', 'title', 'created_at'])
  .where('published', equals: true)
  .where('user_id', equals: userId)
  .orderBy('created_at', descending: true)
  .limit(10)
  .get();

// With joins
final postsWithCommentCount = await database
  .from('posts')
  .select(['posts.*'])
  .selectCount('comments.id', as: 'comment_count')
  .leftJoin('comments', 'posts.id = comments.post_id')
  .where('posts.published', equals: true)
  .groupBy(['posts.id'])
  .orderBy('posts.created_at', descending: true)
  .get();
```

### Update Operations

#### Simple Updates

```dart
// Update records with WHERE clause
final updatedCount = await database.update(
  'users',
  {'last_login': DateTime.now()},
  where: 'id = ?',
  whereArgs: [userId],
);

print('Updated $updatedCount records');
```

#### Conditional Updates

```dart
// Update multiple fields with complex conditions
await database.update(
  'posts',
  {
    'updated_at': DateTime.now(),
    'view_count': 'view_count + 1',  // Use raw SQL for calculations
  },
  where: 'id = ? AND published = ?',
  whereArgs: [postId, true],
);
```

#### Batch Updates

```dart
await database.batch((batch) {
  // Update multiple posts
  for (final postId in postIds) {
    batch.update(
      'posts',
      {'updated_at': DateTime.now()},
      where: 'id = ?',
      whereArgs: [postId],
    );
  }
});
```

### Delete Operations

#### Simple Deletes

```dart
// Delete specific records
final deletedCount = await database.delete(
  'posts',
  where: 'id = ?',
  whereArgs: [postId],
);
```

#### Soft Delete

```dart
// Soft delete (mark as deleted instead of removing)
await database.update(
  'posts',
  {'deleted_at': DateTime.now()},
  where: 'id = ?',
  whereArgs: [postId],
);

// Query excluding soft-deleted records
final activePosts = await database.query(
  'posts',
  where: 'deleted_at IS NULL',
);
```

#### Cascade Deletes

```dart
// Delete with related records
await database.transaction((txn) async {
  // Delete comments first (to maintain referential integrity)
  await txn.delete('comments', where: 'post_id = ?', whereArgs: [postId]);
  
  // Then delete the post
  await txn.delete('posts', where: 'id = ?', whereArgs: [postId]);
});
```

## Advanced Querying

### Transactions

```dart
// Simple transaction
await database.transaction((txn) async {
  final userId = await txn.insert('users', userData);
  await txn.insert('user_profiles', {'user_id': userId, ...profileData});
});

// Transaction with rollback handling
try {
  await database.transaction((txn) async {
    await txn.delete('posts', where: 'user_id = ?', whereArgs: [userId]);
    await txn.delete('users', where: 'id = ?', whereArgs: [userId]);
  });
} catch (e) {
  print('Transaction failed: $e');
  // Transaction is automatically rolled back
}
```

### Raw SQL Queries

```dart
// Complex analytical queries
final monthlyStats = await database.rawQuery('''
  SELECT 
    strftime('%Y-%m', created_at) as month,
    COUNT(*) as post_count,
    COUNT(DISTINCT user_id) as active_authors,
    AVG(view_count) as avg_views
  FROM posts 
  WHERE published = 1 
    AND created_at >= date('now', '-12 months')
  GROUP BY strftime('%Y-%m', created_at)
  ORDER BY month DESC
''');

// Full-text search (if FTS is enabled)
final searchResults = await database.rawQuery('''
  SELECT p.*, snippet(posts_fts) as snippet
  FROM posts_fts
  JOIN posts p ON posts_fts.rowid = p.id
  WHERE posts_fts MATCH ?
  ORDER BY rank
''', ['flutter OR dart']);
```

### Views and Complex Queries

```dart
// Query views (defined in schema)
final publishedPosts = await database.query('published_posts');

// Parameterized view queries
final userPosts = await database.query(
  'published_posts',
  where: 'author_id = ?',
  whereArgs: [userId],
);
```

### Aggregations

```dart
// Count queries
final userCount = await database.count('users');
final activeUserCount = await database.count(
  'users',
  where: 'is_active = ?',
  whereArgs: [true],
);

// Sum, average, min, max
final stats = await database.rawQuery('''
  SELECT 
    COUNT(*) as total_posts,
    SUM(view_count) as total_views,
    AVG(view_count) as avg_views,
    MIN(created_at) as first_post,
    MAX(created_at) as latest_post
  FROM posts
  WHERE published = 1
''');
```

## Streaming Queries

### Real-time Data Streams

```dart
// Create a stream that updates when data changes
final usersStream = database
  .from('users')
  .where('is_active', equals: true)
  .stream();

// Listen to changes
usersStream.listen((users) {
  print('Active users updated: ${users.length}');
  // Update UI automatically
});
```

### Filtered Streams

```dart
// Stream with complex filtering
final recentPostsStream = database
  .from('posts')
  .where('published', equals: true)
  .where('created_at', greaterThan: DateTime.now().subtract(Duration(days: 7)))
  .orderBy('created_at', descending: true)
  .stream();

// Stream with joins
final postsWithAuthorsStream = database
  .fromView('published_posts')  // Use pre-defined view
  .stream();
```

### Stream Subscriptions

```dart
late StreamSubscription subscription;

void startListening() {
  subscription = database
    .from('notifications')
    .where('user_id', equals: currentUserId)
    .where('read', equals: false)
    .stream()
    .listen((notifications) {
      updateNotificationBadge(notifications.length);
    });
}

void stopListening() {
  subscription.cancel();
}
```

## Error Handling

### Common Error Patterns

```dart
try {
  await database.insert('users', userData);
} on DatabaseException catch (e) {
  if (e.isConstraintError()) {
    // Handle constraint violations (unique, foreign key, etc.)
    print('Constraint error: ${e.message}');
  } else if (e.isNoSuchTableError()) {
    // Handle missing table errors
    print('Table does not exist: ${e.message}');
  } else {
    // Handle other database errors
    print('Database error: ${e.message}');
  }
} catch (e) {
  // Handle other errors
  print('Unexpected error: $e');
}
```

### Validation Errors

```dart
try {
  await database.insert('users', {
    'username': 'a',  // Too short
    'email': 'invalid-email',  // Invalid format
    'age': -5,  // Below minimum
  });
} on ValidationException catch (e) {
  // Handle validation errors
  for (final error in e.errors) {
    print('${error.field}: ${error.message}');
  }
}
```

## Performance Optimization

### Batch Operations

```dart
// Efficient bulk operations
await database.batch((batch) {
  for (final item in largeDataSet) {
    batch.insert('items', item);
  }
});

// Instead of:
// for (final item in largeDataSet) {
//   await database.insert('items', item);  // Inefficient!
// }
```

### Connection Pooling

```dart
// Reuse database connections
class DatabaseManager {
  static DeclarativeDatabase? _instance;
  
  static Future<DeclarativeDatabase> get instance async {
    _instance ??= await DeclarativeDatabase.init(
      path: 'app.db',
      schema: schema,
    );
    return _instance!;
  }
  
  static Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }
}
```

### Query Optimization

```dart
// Use indices effectively
final posts = await database.query(
  'posts',
  where: 'user_id = ? AND published = ?',  // Uses composite index
  whereArgs: [userId, true],
  orderBy: 'created_at DESC',  // Uses index on created_at
);

// Limit result sets
final recentPosts = await database.query(
  'posts',
  where: 'published = ?',
  whereArgs: [true],
  orderBy: 'created_at DESC',
  limit: 20,  // Only fetch what you need
);
```

## Complete Example

Here's a comprehensive example showing various database operations:

```dart
class BlogRepository {
  final DeclarativeDatabase database;
  
  BlogRepository(this.database);
  
  // Create operations
  Future<int> createUser(Map<String, dynamic> userData) async {
    return await database.insert('users', {
      ...userData,
      'created_at': DateTime.now(),
    });
  }
  
  Future<int> createPost(Map<String, dynamic> postData) async {
    return await database.transaction((txn) async {
      final postId = await txn.insert('posts', {
        ...postData,
        'created_at': DateTime.now(),
        'updated_at': DateTime.now(),
      });
      
      // Update user's post count
      await txn.rawUpdate('''
        UPDATE users 
        SET post_count = post_count + 1 
        WHERE id = ?
      ''', [postData['user_id']]);
      
      return postId;
    });
  }
  
  // Read operations
  Future<List<Map<String, dynamic>>> getPublishedPosts({
    int? userId,
    int limit = 20,
    int offset = 0,
  }) async {
    final whereConditions = ['published = ?'];
    final whereArgs = [true];
    
    if (userId != null) {
      whereConditions.add('user_id = ?');
      whereArgs.add(userId);
    }
    
    return await database.query(
      'posts',
      where: whereConditions.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }
  
  Stream<List<Map<String, dynamic>>> getPostsStream(int userId) {
    return database
      .from('posts')
      .where('user_id', equals: userId)
      .orderBy('created_at', descending: true)
      .stream();
  }
  
  // Update operations
  Future<void> updatePost(int postId, Map<String, dynamic> updates) async {
    await database.update(
      'posts',
      {
        ...updates,
        'updated_at': DateTime.now(),
      },
      where: 'id = ?',
      whereArgs: [postId],
    );
  }
  
  Future<void> incrementViewCount(int postId) async {
    await database.rawUpdate('''
      UPDATE posts 
      SET view_count = view_count + 1,
          updated_at = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), postId]);
  }
  
  // Delete operations
  Future<void> deletePost(int postId) async {
    await database.transaction((txn) async {
      // Get user_id before deleting
      final post = await txn.queryFirst(
        'posts',
        columns: ['user_id'],
        where: 'id = ?',
        whereArgs: [postId],
      );
      
      if (post != null) {
        // Delete the post
        await txn.delete('posts', where: 'id = ?', whereArgs: [postId]);
        
        // Update user's post count
        await txn.rawUpdate('''
          UPDATE users 
          SET post_count = post_count - 1 
          WHERE id = ?
        ''', [post['user_id']]);
      }
    });
  }
  
  // Analytics
  Future<Map<String, dynamic>> getUserStats(int userId) async {
    final result = await database.rawQuery('''
      SELECT 
        COUNT(*) as total_posts,
        COUNT(CASE WHEN published = 1 THEN 1 END) as published_posts,
        SUM(view_count) as total_views,
        AVG(view_count) as avg_views,
        MAX(created_at) as latest_post
      FROM posts 
      WHERE user_id = ?
    ''', [userId]);
    
    return result.first;
  }
}
```

## Next Steps

- Learn about [Streaming Queries](./streaming-queries) for real-time applications
- Explore [Sync Management](./sync-management) for offline-first apps
- Understand [Fileset Fields](./fileset-fields) for file handling
- See [Migration](./migration) for schema evolution