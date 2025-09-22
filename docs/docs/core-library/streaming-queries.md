# Streaming Queries

Learn how to use real-time streaming queries to build reactive applications that automatically update when data changes.

## Overview

Streaming queries are one of the most powerful features of Declarative SQLite. They provide real-time updates whenever the underlying data changes, enabling reactive user interfaces and responsive applications.

## Basic Streaming

### Simple Streams with Typed Records

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

// Stream all users with type safety
final userStream = database.streamTyped<User>((q) => q.from('users'));

userStream.listen((users) {
  print('Users updated: ${users.length} total users');
  for (final user in users) {
    print('- ${user.name} (${user.email})'); // Type-safe property access
  }
});

// Stream with WHERE clause
final adultUserStream = database.streamTyped<User>((q) => 
  q.from('users').where('age >= ?', [18])
);

adultUserStream.listen((adultUsers) {
  print('Adult users: ${adultUsers.length}');
  for (final user in adultUsers) {
    print('- ${user.name}, age ${user.age}');
  }
});
```

### Direct Query Streams

For cases where you need direct control over queries:

```dart
// Stream all users
final userStream = database.streamQuery('users');
userStream.listen((users) {
  print('Users updated: ${users.length} total users');
  for (final user in users) {
    print('- ${user['name']} (${user['email']})');
  }
});

// Stream with WHERE clause
final adultUserStream = database.streamQuery(
  'users',
  where: 'age >= ?',
  whereArgs: [18],
);

adultUserStream.listen((adultUsers) {
  print('Adult users: ${adultUsers.length}');
});
```

### Stream with Ordering and Limits

Using typed records:

```dart
// Stream recent posts with type safety
final recentPostsStream = database.streamTyped<Post>((q) => 
  q.from('posts')
   .orderBy('created_at DESC')
   .limit(10)
);

recentPostsStream.listen((posts) {
  print('Latest 10 posts updated');
  for (final post in posts) {
    print('- ${post.title} by ${post.authorName}');
  }
});

// Stream top users by post count (using a view)
final topUsersStream = database.streamTyped<UserStats>((q) => 
  q.from('user_post_counts')
   .orderBy('post_count DESC')
   .limit(5)
);

topUsersStream.listen((topUsers) {
  print('Top users updated');
  for (final user in topUsers) {
    print('- ${user.name}: ${user.postCount} posts');
  }
});
```

Using direct queries:

```dart
// Stream recent posts
final recentPostsStream = database.streamQuery(
  'posts',
  orderBy: 'created_at DESC',
  limit: 10,
);

recentPostsStream.listen((posts) {
  print('Latest 10 posts updated');
  // UI will automatically update when new posts are added
});

// Stream top users by post count
final topUsersStream = database.streamQuery(
  'user_post_counts', // This could be a view
  orderBy: 'post_count DESC',
  limit: 5,
);
```

## Advanced Streaming Queries

### Multiple Table Dependencies

Advanced streaming queries can depend on multiple tables and automatically update when any dependency changes:

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

// Create an advanced streaming query that depends on multiple tables
final advancedQuery = AdvancedStreamingQuery(
  database: database,
  query: '''
    SELECT 
      posts.id,
      posts.title,
      posts.content,
      users.name as author_name,
      COUNT(comments.id) as comment_count
    FROM posts
    JOIN users ON posts.user_id = users.id
    LEFT JOIN comments ON posts.id = comments.post_id
    WHERE posts.published = 1
    GROUP BY posts.id, posts.title, posts.content, users.name
    ORDER BY posts.created_at DESC
  ''',
  dependencies: ['posts', 'users', 'comments'],
);

final stream = advancedQuery.stream();
stream.listen((results) {
  print('Post data updated: ${results.length} posts');
  // This will update when:
  // - New posts are added/modified
  // - User names change
  // - Comments are added/removed
});
```

### Custom Query Dependencies

You can manually specify which tables should trigger updates:

```dart
final customQuery = AdvancedStreamingQuery(
  database: database,
  query: '''
    SELECT products.*, categories.name as category_name
    FROM products
    JOIN categories ON products.category_id = categories.id
    WHERE products.active = 1
  ''',
  dependencies: ['products', 'categories'],
);

// Stream will update when products or categories change
final productStream = customQuery.stream();
```

## Practical Examples

### User Profile with Posts

```dart
class UserProfileStream {
  final DeclarativeDatabase database;
  final String userId;
  
  UserProfileStream(this.database, this.userId);
  
  // Stream user profile data
  Stream<Map<String, Object?>> get userStream {
    return database.streamQuery(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    ).map((users) => users.isNotEmpty ? users.first : {});
  }
  
  // Stream user's posts
  Stream<List<Map<String, Object?>>> get postsStream {
    return database.streamQuery(
      'posts',
      where: 'user_id = ? AND published = 1',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
  }
  
  // Stream user statistics
  Stream<Map<String, Object?>> get statsStream {
    final query = AdvancedStreamingQuery(
      database: database,
      query: '''
        SELECT 
          COUNT(posts.id) as post_count,
          COUNT(CASE WHEN posts.created_at > ? THEN 1 END) as recent_posts,
          MAX(posts.created_at) as latest_post_date
        FROM posts
        WHERE posts.user_id = ?
      ''',
      dependencies: ['posts'],
      parameters: [
        DateTime.now().subtract(Duration(days: 30)).toIso8601String(),
        userId,
      ],
    );
    
    return query.stream().map((results) => 
      results.isNotEmpty ? results.first : {});
  }
}

// Usage
final userProfile = UserProfileStream(database, 'user-123');

userProfile.userStream.listen((user) {
  print('User profile updated: ${user['name']}');
});

userProfile.postsStream.listen((posts) {
  print('User posts updated: ${posts.length} posts');
});

userProfile.statsStream.listen((stats) {
  print('User stats: ${stats['post_count']} total posts, ${stats['recent_posts']} recent');
});
```

### Shopping Cart with Live Totals

```dart
class ShoppingCartStream {
  final DeclarativeDatabase database;
  final String cartId;
  
  ShoppingCartStream(this.database, this.cartId);
  
  // Stream cart items with product details
  Stream<List<Map<String, Object?>>> get itemsStream {
    final query = AdvancedStreamingQuery(
      database: database,
      query: '''
        SELECT 
          cart_items.id,
          cart_items.quantity,
          products.name,
          products.price,
          (cart_items.quantity * products.price) as line_total
        FROM cart_items
        JOIN products ON cart_items.product_id = products.id
        WHERE cart_items.cart_id = ?
        ORDER BY cart_items.added_at DESC
      ''',
      dependencies: ['cart_items', 'products'],
      parameters: [cartId],
    );
    
    return query.stream();
  }
  
  // Stream cart totals
  Stream<Map<String, Object?>> get totalsStream {
    final query = AdvancedStreamingQuery(
      database: database,
      query: '''
        SELECT 
          COUNT(cart_items.id) as item_count,
          SUM(cart_items.quantity) as total_quantity,
          SUM(cart_items.quantity * products.price) as total_amount
        FROM cart_items
        JOIN products ON cart_items.product_id = products.id
        WHERE cart_items.cart_id = ?
      ''',
      dependencies: ['cart_items', 'products'],
      parameters: [cartId],
    );
    
    return query.stream().map((results) => 
      results.isNotEmpty ? results.first : {
        'item_count': 0,
        'total_quantity': 0,
        'total_amount': 0.0,
      });
  }
}

// Usage
final cart = ShoppingCartStream(database, 'cart-456');

cart.itemsStream.listen((items) {
  print('Cart items updated: ${items.length} different products');
  for (final item in items) {
    print('- ${item['name']}: ${item['quantity']} × \$${item['price']} = \$${item['line_total']}');
  }
});

cart.totalsStream.listen((totals) {
  print('Cart total: \$${totals['total_amount']} (${totals['total_quantity']} items)');
});
```

## Stream Performance Optimization

### Debouncing Updates

When multiple rapid changes occur, you may want to debounce the stream:

```dart
import 'dart:async';

extension StreamDebounce<T> on Stream<T> {
  Stream<T> debounce(Duration duration) {
    Timer? timer;
    T? lastValue;
    late StreamController<T> controller;
    
    controller = StreamController<T>(
      onListen: () {
        listen((value) {
          lastValue = value;
          timer?.cancel();
          timer = Timer(duration, () {
            controller.add(lastValue as T);
          });
        });
      },
      onCancel: () {
        timer?.cancel();
      },
    );
    
    return controller.stream;
  }
}

// Usage
final debouncedUserStream = database
  .streamQuery('users')
  .debounce(Duration(milliseconds: 300));

debouncedUserStream.listen((users) {
  // Only updates every 300ms maximum, even if data changes more frequently
  print('Debounced user update: ${users.length} users');
});
```

### Filtering Duplicate Updates

```dart
// Only emit when the actual data changes, not just query execution
final distinctUserStream = database
  .streamQuery('users')
  .distinct((previous, current) {
    // Compare the actual data, not just reference
    return previous.length == current.length &&
           previous.every((prevUser) => 
             current.any((currUser) => 
               currUser['id'] == prevUser['id'] && 
               currUser['name'] == prevUser['name']));
  });
```

## Stream Lifecycle Management

### Proper Subscription Management

```dart
class UserListManager {
  DeclarativeDatabase database;
  StreamSubscription<List<Map<String, Object?>>>? _userSubscription;
  
  UserListManager(this.database);
  
  void startListening() {
    _userSubscription = database.streamQuery('users').listen(
      (users) {
        // Handle user updates
        _updateUI(users);
      },
      onError: (error) {
        print('Stream error: $error');
        // Handle error - maybe retry or show error message
      },
    );
  }
  
  void stopListening() {
    _userSubscription?.cancel();
    _userSubscription = null;
  }
  
  void _updateUI(List<Map<String, Object?>> users) {
    // Update your UI with new user data
    print('UI updated with ${users.length} users');
  }
  
  void dispose() {
    stopListening();
  }
}
```

### Multiple Stream Coordination

```dart
class DashboardManager {
  final DeclarativeDatabase database;
  final _subscriptions = <StreamSubscription>[];
  
  DashboardManager(this.database);
  
  void initialize() {
    // Listen to multiple streams
    _subscriptions.add(
      database.streamQuery('users').listen(_updateUserCount)
    );
    
    _subscriptions.add(
      database.streamQuery('posts', where: 'published = 1').listen(_updatePostCount)
    );
    
    _subscriptions.add(
      database.streamQuery('comments', where: 'approved = 1').listen(_updateCommentCount)
    );
  }
  
  void _updateUserCount(List<Map<String, Object?>> users) {
    print('Users: ${users.length}');
  }
  
  void _updatePostCount(List<Map<String, Object?>> posts) {
    print('Published posts: ${posts.length}');
  }
  
  void _updateCommentCount(List<Map<String, Object?>> comments) {
    print('Approved comments: ${comments.length}');
  }
  
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
```

## Integration with State Management

### With Flutter setState

```dart
class UserListWidget extends StatefulWidget {
  @override
  _UserListWidgetState createState() => _UserListWidgetState();
}

class _UserListWidgetState extends State<UserListWidget> {
  List<Map<String, Object?>> users = [];
  StreamSubscription<List<Map<String, Object?>>>? _subscription;
  
  @override
  void initState() {
    super.initState();
    final database = DatabaseProvider.of(context);
    
    _subscription = database.streamQuery('users').listen((newUsers) {
      setState(() {
        users = newUsers;
      });
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return ListTile(
          title: Text(user['name'] as String),
          subtitle: Text(user['email'] as String),
        );
      },
    );
  }
}
```

### With Provider/Riverpod

```dart
// Using Provider
class UserNotifier extends ChangeNotifier {
  List<Map<String, Object?>> _users = [];
  StreamSubscription<List<Map<String, Object?>>>? _subscription;
  
  List<Map<String, Object?>> get users => _users;
  
  void initialize(DeclarativeDatabase database) {
    _subscription = database.streamQuery('users').listen((users) {
      _users = users;
      notifyListeners();
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

// Using Riverpod
final userStreamProvider = StreamProvider<List<Map<String, Object?>>>((ref) {
  final database = ref.read(databaseProvider);
  return database.streamQuery('users');
});
```

## Error Handling

### Stream Error Recovery

```dart
Stream<List<Map<String, Object?>>> createResilientUserStream(DeclarativeDatabase database) {
  return database.streamQuery('users').handleError((error) {
    print('Stream error: $error');
    // Log error or notify error reporting service
  }).onErrorResumeNext(
    // Retry with exponential backoff
    Stream.fromFuture(
      Future.delayed(Duration(seconds: 2)).then((_) => 
        createResilientUserStream(database)
      )
    ).asyncExpand((stream) => stream),
  );
}
```

### Graceful Degradation

```dart
class RobustUserStream {
  final DeclarativeDatabase database;
  StreamSubscription<List<Map<String, Object?>>>? _subscription;
  List<Map<String, Object?>> _lastKnownUsers = [];
  
  RobustUserStream(this.database);
  
  Stream<List<Map<String, Object?>>> get stream {
    return Stream.fromFuture(_getInitialData())
      .asyncExpand((_) => _createStream());
  }
  
  Future<void> _getInitialData() async {
    try {
      _lastKnownUsers = await database.query('users');
    } catch (e) {
      print('Failed to get initial data: $e');
      // Use empty list or cached data
    }
  }
  
  Stream<List<Map<String, Object?>>> _createStream() async* {
    yield _lastKnownUsers; // Emit initial data
    
    yield* database.streamQuery('users').map((users) {
      _lastKnownUsers = users; // Cache successful results
      return users;
    }).handleError((error) {
      print('Stream error, using cached data: $error');
      return _lastKnownUsers; // Return last known good data
    });
  }
}
```

## Best Practices

### Memory Management

```dart
// ✅ Good - Cancel subscriptions
class DataManager {
  final _subscriptions = <StreamSubscription>[];
  
  void addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }
  
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}

// ❌ Bad - Memory leak
void badExample(DeclarativeDatabase database) {
  database.streamQuery('users').listen((users) {
    // This subscription is never cancelled!
  });
}
```

### Efficient Queries

```dart
// ✅ Good - Specific columns and conditions
final efficientStream = database.streamQuery(
  'users',
  columns: ['id', 'name', 'email'], // Only needed columns
  where: 'active = 1', // Filter at database level
  limit: 100, // Limit result size
);

// ❌ Bad - Unnecessary data
final inefficientStream = database.streamQuery('users'); // All columns, all rows
```

### Reactive Architecture

```dart
class ReactiveUserService {
  final DeclarativeDatabase _database;
  
  ReactiveUserService(this._database);
  
  // Expose specific streams for different UI components
  Stream<List<Map<String, Object?>>> get activeUsers => 
    _database.streamQuery('users', where: 'active = 1');
    
  Stream<List<Map<String, Object?>>> get recentUsers =>
    _database.streamQuery(
      'users',
      where: 'created_at > ?',
      whereArgs: [DateTime.now().subtract(Duration(days: 7)).toIso8601String()],
      orderBy: 'created_at DESC',
    );
    
  Stream<int> get userCount =>
    _database.streamQuery('users').map((users) => users.length);
}
```

## Next Steps

Now that you understand streaming queries, explore:

- [Typed Records](typed-records) - Work with typed record classes in streams
- [Exception Handling](exception-handling) - Handle stream errors gracefully  
- [Advanced Features](advanced-features) - Garbage collection and utilities
- [Flutter Integration](../flutter-integration/widgets) - Using streams with Flutter widgets