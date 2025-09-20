---
sidebar_position: 4
---

# Streaming Queries

Build reactive applications with real-time data updates using Declarative SQLite's powerful streaming query system.

## Overview

Streaming queries allow your application to automatically receive updates when underlying data changes. Instead of manually polling the database or managing complex refresh logic, you simply subscribe to a stream and your UI updates automatically.

## Basic Streaming

### Creating a Stream

```dart
// Create a stream of all users
final usersStream = database
  .from('users')
  .stream();

// Listen to changes
usersStream.listen((users) {
  print('Users updated: ${users.length}');
  // Update your UI here
});
```

### Filtered Streams

```dart
// Stream only active users
final activeUsersStream = database
  .from('users')
  .where('is_active', equals: true)
  .stream();

// Stream recent posts
final recentPostsStream = database
  .from('posts')
  .where('created_at', greaterThan: DateTime.now().subtract(Duration(days: 7)))
  .where('published', equals: true)
  .orderBy('created_at', descending: true)
  .stream();
```

## Query Builder Streaming

### Simple Queries

```dart
// Stream all posts by a specific user
final userPostsStream = database
  .from('posts')
  .where('user_id', equals: userId)
  .orderBy('created_at', descending: true)
  .stream();

// Stream with multiple conditions
final featuredPostsStream = database
  .from('posts')
  .where('published', equals: true)
  .where('featured', equals: true)
  .where('view_count', greaterThan: 1000)
  .stream();
```

### Complex Filtering

```dart
// Stream with date ranges
final thisWeekPostsStream = database
  .from('posts')
  .where('created_at', between: [
    DateTime.now().subtract(Duration(days: 7)),
    DateTime.now()
  ])
  .stream();

// Stream with text search
final searchResultsStream = database
  .from('posts')
  .where('title', contains: searchTerm)
  .or('content', contains: searchTerm)
  .where('published', equals: true)
  .stream();

// Stream with ordering and limits
final topPostsStream = database
  .from('posts')
  .where('published', equals: true)
  .orderBy('view_count', descending: true)
  .limit(10)
  .stream();
```

## Advanced Streaming

### Joined Streams

```dart
// Stream posts with author information using views
final postsWithAuthorsStream = database
  .fromView('posts_with_authors')  // Pre-defined view in schema
  .where('published', equals: true)
  .stream();

// Stream with manual joins (using raw SQL)
final postsWithCommentsStream = database
  .rawStreamQuery('''
    SELECT 
      p.*,
      u.username as author,
      COUNT(c.id) as comment_count
    FROM posts p
    LEFT JOIN users u ON p.user_id = u.id
    LEFT JOIN comments c ON p.id = c.post_id
    WHERE p.published = 1
    GROUP BY p.id, u.username
    ORDER BY p.created_at DESC
  ''')
  .stream();
```

### Aggregated Streams

```dart
// Stream user statistics
final userStatsStream = database
  .rawStreamQuery('''
    SELECT 
      user_id,
      COUNT(*) as post_count,
      SUM(view_count) as total_views,
      AVG(view_count) as avg_views,
      MAX(created_at) as latest_post
    FROM posts
    WHERE published = 1
    GROUP BY user_id
    ORDER BY total_views DESC
  ''')
  .stream();

// Stream real-time dashboard data
final dashboardStream = database
  .rawStreamQuery('''
    SELECT 
      (SELECT COUNT(*) FROM users WHERE is_active = 1) as active_users,
      (SELECT COUNT(*) FROM posts WHERE published = 1) as published_posts,
      (SELECT COUNT(*) FROM comments WHERE created_at > datetime('now', '-24 hours')) as recent_comments
  ''')
  .stream();
```

## Stream Management

### Subscription Handling

```dart
class PostListController {
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  final List<Map<String, dynamic>> _posts = [];
  final StreamController<List<Map<String, dynamic>>> _controller = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  
  Stream<List<Map<String, dynamic>>> get posts => _controller.stream;
  
  void startListening(DeclarativeDatabase database, int userId) {
    _subscription = database
      .from('posts')
      .where('user_id', equals: userId)
      .where('published', equals: true)
      .orderBy('created_at', descending: true)
      .stream()
      .listen((posts) {
        _posts.clear();
        _posts.addAll(posts);
        _controller.add(List.from(_posts));
      });
  }
  
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
  
  void dispose() {
    stopListening();
    _controller.close();
  }
}
```

### Multiple Stream Coordination

```dart
class AppDataManager {
  final DeclarativeDatabase database;
  late final StreamSubscription _usersSubscription;
  late final StreamSubscription _postsSubscription;
  late final StreamSubscription _commentsSubscription;
  
  final _dataController = StreamController<AppData>.broadcast();
  Stream<AppData> get dataStream => _dataController.stream;
  
  AppDataManager(this.database);
  
  void startListening() {
    // Combine multiple streams
    _usersSubscription = database
      .from('users')
      .where('is_active', equals: true)
      .stream()
      .listen(_onUsersChanged);
      
    _postsSubscription = database
      .from('posts')
      .where('published', equals: true)
      .stream()
      .listen(_onPostsChanged);
      
    _commentsSubscription = database
      .from('comments')
      .where('approved', equals: true)
      .stream()
      .listen(_onCommentsChanged);
  }
  
  void _onUsersChanged(List<Map<String, dynamic>> users) {
    // Update combined state and emit
    _emitCombinedData();
  }
  
  void _onPostsChanged(List<Map<String, dynamic>> posts) {
    _emitCombinedData();
  }
  
  void _onCommentsChanged(List<Map<String, dynamic>> comments) {
    _emitCombinedData();
  }
  
  void _emitCombinedData() {
    // Combine all data and emit to listeners
    final combinedData = AppData(
      users: _currentUsers,
      posts: _currentPosts,
      comments: _currentComments,
    );
    _dataController.add(combinedData);
  }
  
  void dispose() {
    _usersSubscription.cancel();
    _postsSubscription.cancel();
    _commentsSubscription.cancel();
    _dataController.close();
  }
}
```

## Stream Transformations

### Data Transformation

```dart
// Transform raw data into typed objects
final userModelsStream = database
  .from('users')
  .stream()
  .map((rawUsers) => rawUsers
      .map((userData) => UserModel.fromMap(userData))
      .toList());

// Filter and transform
final recentUserPostsStream = database
  .from('posts')
  .where('user_id', equals: userId)
  .stream()
  .map((posts) => posts
      .where((post) => DateTime.parse(post['created_at'])
          .isAfter(DateTime.now().subtract(Duration(days: 30))))
      .map((post) => PostModel.fromMap(post))
      .toList());
```

### Stream Combination

```dart
// Combine multiple streams using StreamZip or combineLatest
import 'package:rxdart/rxdart.dart';

final combinedStream = Rx.combineLatest2(
  database.from('users').stream(),
  database.from('posts').stream(),
  (List<Map<String, dynamic>> users, List<Map<String, dynamic>> posts) {
    return CombinedData(users: users, posts: posts);
  },
);
```

### Debouncing and Throttling

```dart
// Debounce rapid changes
final debouncedStream = database
  .from('search_results')
  .stream()
  .debounceTime(Duration(milliseconds: 300));

// Throttle updates
final throttledStream = database
  .from('realtime_data')
  .stream()
  .throttleTime(Duration(seconds: 1));
```

## Performance Optimization

### Stream Caching

```dart
class StreamCache {
  final Map<String, Stream> _cache = {};
  
  Stream<List<Map<String, dynamic>>> getCachedStream(
    String key,
    Stream<List<Map<String, dynamic>>> Function() createStream,
  ) {
    return _cache.putIfAbsent(key, () => createStream().asBroadcastStream());
  }
  
  void clearCache() {
    _cache.clear();
  }
}

// Usage
final cache = StreamCache();

final usersStream = cache.getCachedStream(
  'active_users',
  () => database.from('users').where('is_active', equals: true).stream(),
);
```

### Selective Updates

```dart
// Only emit when specific fields change
final importantFieldsStream = database
  .from('users')
  .select(['id', 'username', 'email', 'is_active'])  // Only watch these fields
  .stream()
  .distinct((a, b) => 
    const ListEquality().equals(a, b));  // Only emit on actual changes
```

### Memory Management

```dart
class MemoryEfficientStreamManager {
  final Map<String, StreamSubscription> _subscriptions = {};
  
  void addSubscription(String key, StreamSubscription subscription) {
    // Cancel existing subscription if any
    _subscriptions[key]?.cancel();
    _subscriptions[key] = subscription;
  }
  
  void removeSubscription(String key) {
    _subscriptions[key]?.cancel();
    _subscriptions.remove(key);
  }
  
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
```

## Flutter Integration

### StreamBuilder Usage

```dart
class PostsList extends StatelessWidget {
  final int userId;
  
  const PostsList({Key? key, required this.userId}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final database = DatabaseProvider.of(context);
    
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: database
        .from('posts')
        .where('user_id', equals: userId)
        .where('published', equals: true)
        .orderBy('created_at', descending: true)
        .stream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorWidget(snapshot.error!);
        }
        
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        
        final posts = snapshot.data!;
        
        if (posts.isEmpty) {
          return const Text('No posts found');
        }
        
        return ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return PostCard(post: post);
          },
        );
      },
    );
  }
}
```

### Custom Stream Widgets

```dart
class QueryStreamBuilder<T> extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> stream;
  final T Function(Map<String, dynamic>) mapper;
  final Widget Function(BuildContext, List<T>) builder;
  final Widget? loading;
  final Widget Function(Object error)? errorBuilder;
  
  const QueryStreamBuilder({
    Key? key,
    required this.stream,
    required this.mapper,
    required this.builder,
    this.loading,
    this.errorBuilder,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return errorBuilder?.call(snapshot.error!) ?? 
            ErrorWidget(snapshot.error!);
        }
        
        if (!snapshot.hasData) {
          return loading ?? const CircularProgressIndicator();
        }
        
        final mappedData = snapshot.data!.map(mapper).toList();
        return builder(context, mappedData);
      },
    );
  }
}

// Usage
QueryStreamBuilder<PostModel>(
  stream: database.from('posts').stream(),
  mapper: (data) => PostModel.fromMap(data),
  builder: (context, posts) {
    return ListView(
      children: posts.map((post) => PostCard(post: post)).toList(),
    );
  },
)
```

## Testing Streams

### Stream Testing

```dart
// Test file: test/streaming_test.dart
import 'package:test/test.dart';

void main() {
  group('Streaming Tests', () {
    late DeclarativeDatabase database;
    
    setUp(() async {
      database = await DeclarativeDatabase.init(
        path: ':memory:',
        schema: testSchema,
      );
    });
    
    tearDown(() async {
      await database.close();
    });
    
    test('should stream user updates', () async {
      final stream = database.from('users').stream();
      final streamTest = expectLater(
        stream,
        emitsInOrder([
          isEmpty,  // Initial empty state
          hasLength(1),  // After first insert
          hasLength(2),  // After second insert
        ]),
      );
      
      // Insert test data
      await database.insert('users', {'username': 'user1'});
      await database.insert('users', {'username': 'user2'});
      
      await streamTest;
    });
    
    test('should filter streams correctly', () async {
      // Insert test data
      await database.insert('users', {'username': 'active', 'is_active': true});
      await database.insert('users', {'username': 'inactive', 'is_active': false});
      
      final activeUsersStream = database
        .from('users')
        .where('is_active', equals: true)
        .stream();
      
      await expectLater(
        activeUsersStream,
        emits(hasLength(1)),
      );
    });
  });
}
```

## Complete Example

Here's a comprehensive example of using streaming queries in a real application:

```dart
class BlogStreamManager {
  final DeclarativeDatabase database;
  final Map<String, StreamSubscription> _subscriptions = {};
  
  // Stream controllers for different data types
  final _postsController = StreamController<List<PostModel>>.broadcast();
  final _usersController = StreamController<List<UserModel>>.broadcast();
  final _statsController = StreamController<BlogStats>.broadcast();
  
  // Public streams
  Stream<List<PostModel>> get posts => _postsController.stream;
  Stream<List<UserModel>> get users => _usersController.stream;
  Stream<BlogStats> get stats => _statsController.stream;
  
  BlogStreamManager(this.database);
  
  void startStreaming() {
    // Stream published posts
    _subscriptions['posts'] = database
      .from('posts')
      .where('published', equals: true)
      .orderBy('created_at', descending: true)
      .stream()
      .map((data) => data.map((item) => PostModel.fromMap(item)).toList())
      .listen(_postsController.add);
    
    // Stream active users
    _subscriptions['users'] = database
      .from('users')
      .where('is_active', equals: true)
      .stream()
      .map((data) => data.map((item) => UserModel.fromMap(item)).toList())
      .listen(_usersController.add);
    
    // Stream blog statistics
    _subscriptions['stats'] = database
      .rawStreamQuery('''
        SELECT 
          (SELECT COUNT(*) FROM posts WHERE published = 1) as published_posts,
          (SELECT COUNT(*) FROM users WHERE is_active = 1) as active_users,
          (SELECT SUM(view_count) FROM posts WHERE published = 1) as total_views,
          (SELECT COUNT(*) FROM comments WHERE created_at > datetime('now', '-24 hours')) as recent_comments
      ''')
      .stream()
      .map((data) => BlogStats.fromMap(data.first))
      .listen(_statsController.add);
  }
  
  void stopStreaming() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
  
  void dispose() {
    stopStreaming();
    _postsController.close();
    _usersController.close();
    _statsController.close();
  }
  
  // Utility methods for specific queries
  Stream<List<PostModel>> getPostsByUser(int userId) {
    return database
      .from('posts')
      .where('user_id', equals: userId)
      .where('published', equals: true)
      .stream()
      .map((data) => data.map((item) => PostModel.fromMap(item)).toList());
  }
  
  Stream<List<PostModel>> searchPosts(String searchTerm) {
    return database
      .rawStreamQuery('''
        SELECT * FROM posts 
        WHERE published = 1 
        AND (title LIKE ? OR content LIKE ?)
        ORDER BY created_at DESC
      ''', ['%$searchTerm%', '%$searchTerm%'])
      .stream()
      .map((data) => data.map((item) => PostModel.fromMap(item)).toList());
  }
}
```

## Next Steps

- Learn about [Sync Management](#sync-management) (coming soon) for offline-first applications
- Explore [Fileset Fields](#fileset-fields) (coming soon) for file handling
- See [Flutter Integration](../flutter/installation) for UI components
- Check out [Performance Tips](#performance) (coming soon) for optimization