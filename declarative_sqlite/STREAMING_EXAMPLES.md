# Streaming Query Results - Usage Examples

The declarative_sqlite package now supports streaming query results that automatically update when the underlying data changes.

## Basic Usage

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

// Create a streaming query
final usersStream = db.stream<Map<String, Object?>>(
  (q) => q.from('users').where(col('status').eq('active')),
  (row) => row, // Identity mapper
);

// Listen to changes
usersStream.listen((users) {
  print('Active users updated: ${users.length}');
  for (final user in users) {
    print('  - ${user['name']} (${user['age']})');
  }
});

// Data changes will automatically trigger stream updates
await db.insert('users', {'name': 'Alice', 'age': 30, 'status': 'active'});
// Stream emits: [Alice]

await db.insert('users', {'name': 'Bob', 'age': 25, 'status': 'active'});  
// Stream emits: [Alice, Bob]

await db.update('users', {'status': 'inactive'}, where: 'name = ?', whereArgs: ['Alice']);
// Stream emits: [Bob] (Alice filtered out)
```

## With Custom Mappers

```dart
class User {
  final String name;
  final int age;
  final String status;
  
  User({required this.name, required this.age, required this.status});
  
  static User fromMap(Map<String, Object?> map) => User(
    name: map['name'] as String,
    age: map['age'] as int, 
    status: map['status'] as String,
  );
  
  @override
  String toString() => 'User($name, $age, $status)';
}

// Stream with custom mapping
final usersStream = db.stream<User>(
  (q) => q.from('users').where(col('age').gte(18)),
  User.fromMap,
);

usersStream.listen((users) {
  print('Adult users: ${users.map((u) => u.toString()).join(', ')}');
});
```

## Multiple Streams

```dart
// Different streams can monitor different aspects of the data
final activeUsersStream = db.stream<User>(
  (q) => q.from('users').where(col('status').eq('active')),
  User.fromMap,
);

final teenUsersStream = db.stream<User>(
  (q) => q.from('users').where(col('age').between(13, 19)),
  User.fromMap,
);

// Both will update independently when relevant data changes
activeUsersStream.listen((users) => print('Active: ${users.length}'));
teenUsersStream.listen((users) => print('Teens: ${users.length}'));

// This will trigger both streams if the user is an active teen
await db.insert('users', {'name': 'Charlie', 'age': 16, 'status': 'active'});
```

## Complex Queries with JOINs

```dart
// Streams work with complex queries including JOINs
final userPostsStream = db.stream<Map<String, Object?>>(
  (q) => q
    .select('u.name')
    .select('COUNT(p.id)', 'post_count')
    .from('users', 'u')
    .leftJoin('posts', 'u.id = p.user_id', 'p')
    .groupBy(['u.id', 'u.name'])
    .having('COUNT(p.id) > 0'),
  (row) => row,
);

userPostsStream.listen((results) {
  print('Users with posts:');
  for (final row in results) {
    print('  ${row['name']}: ${row['post_count']} posts');
  }
});

// Will update when users or posts tables change
await db.insert('posts', {'user_id': 1, 'title': 'New Post', 'content': '...'});
```

## Flutter Widget Integration

```dart
// Use with QueryListView for reactive UI
QueryListView<User>(
  database: db,
  query: (q) => q.from('users').where(col('status').eq('active')),
  mapper: User.fromMap,
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
  itemBuilder: (context, user) => ListTile(
    title: Text(user.name),
    subtitle: Text('Age: ${user.age}'),
  ),
)
```

## How It Works

The streaming system automatically:

1. **Analyzes Dependencies**: Parses your query to understand which tables and columns it depends on
2. **Monitors Changes**: Hooks into insert, update, delete, and bulkLoad operations
3. **Smart Updates**: Only re-executes queries when changes affect their dependencies
4. **Efficient Emission**: Only emits new results when the data actually changes (no duplicate emissions)

### Supported Operations

All of these operations will trigger stream updates for affected queries:
- `db.insert()` - Triggers streams querying the target table
- `db.update()` - Triggers streams querying the target table  
- `db.delete()` - Triggers streams querying the target table
- `db.bulkLoad()` - Triggers streams querying the target table

### Performance Notes

- Multiple affected queries are refreshed concurrently
- Inactive streams are automatically cleaned up
- Query results are compared to avoid unnecessary emissions
- Memory usage is optimized through proper stream disposal