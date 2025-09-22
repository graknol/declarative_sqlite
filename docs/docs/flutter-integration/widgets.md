# Flutter Integration

Learn how to use Declarative SQLite's Flutter widgets to build reactive, data-driven user interfaces.

## Overview

The `declarative_sqlite_flutter` package provides Flutter-specific widgets and utilities that seamlessly integrate with the core library. These widgets automatically update when data changes, creating truly reactive user interfaces.

## Core Widgets

### DatabaseProvider

The `DatabaseProvider` is an InheritedWidget that manages database lifecycle and provides access throughout your widget tree:

```dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      home: DatabaseProvider(
        schema: buildSchema,
        databaseName: 'app.db',
        child: HomeScreen(),
      ),
    );
  }
}

void buildSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.text('email').notNull();
    table.key(['id']).primary();
  });
}
```

#### DatabaseProvider Configuration

```dart
DatabaseProvider(
  schema: buildSchema,
  databaseName: 'my_app.db',
  
  // Optional: Custom database path
  databasePath: '/custom/path/to/database/',
  
  // Optional: Enable logging
  enableLogging: true,
  
  // Optional: Custom initialization
  onInitialize: (database) async {
    // Perform custom setup after database creation
    await database.insert('settings', {
      'id': 'app-config',
      'theme': 'light',
      'notifications': true,
    });
  },
  
  child: MyApp(),
)
```

#### Accessing the Database

```dart
class SomeWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Get database instance
    final database = DatabaseProvider.of(context);
    
    return ElevatedButton(
      onPressed: () async {
        // Using typed records (recommended)
        final newUser = User.create(database);
        newUser.name = 'New User';
        newUser.email = 'user@example.com';
        await newUser.save();
        
        // Or using raw maps
        await database.insert('users', {
          'id': 'user-${DateTime.now().millisecondsSinceEpoch}',
          'name': 'New User',
          'email': 'user@example.com',
        });
      },
      child: Text('Add User'),
    );
  }
}
```

### QueryListView

The `QueryListView` is a reactive ListView that automatically updates when database data changes:

```dart
class UserListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Users')),
      body: QueryListView<User>(
        database: DatabaseProvider.of(context),
        
        // Define the query
        query: (q) => q
          .from('users')
          .where('active = 1')
          .orderBy('name ASC'),
          
        // Map database rows to data objects
        mapper: User.fromMap,
        
        // Build individual list items
        itemBuilder: (context, user) => UserCard(user: user),
        
        // Optional: Loading state
        loadingBuilder: (context) => Center(
          child: CircularProgressIndicator(),
        ),
        
        // Optional: Error state
        errorBuilder: (context, error) => Center(
          child: Text('Error: $error'),
        ),
        
        // Optional: Empty state
        emptyBuilder: (context) => Center(
          child: Text('No users found'),
        ),
        
        // ListView properties
        padding: EdgeInsets.all(16),
        physics: BouncingScrollPhysics(),
      ),
    );
  }
}

class User {
  final String id;
  final String name;
  final String email;

  User({required this.id, required this.name, required this.email});

  static User fromMap(Map<String, Object?> map) {
    return User(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
    );
  }
}

class UserCard extends StatelessWidget {
  final User user;
  
  UserCard({required this.user});
  
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(user.name[0].toUpperCase()),
        ),
        title: Text(user.name),
        subtitle: Text(user.email),
        onTap: () => _showUserDetails(context),
      ),
    );
  }
  
  void _showUserDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserDetailScreen(user: user),
      ),
    );
  }
}
```

#### QueryListView Advanced Features

```dart
QueryListView<Post>(
  database: DatabaseProvider.of(context),
  
  // Complex query with joins
  query: (q) => q.rawQuery('''
    SELECT posts.*, users.name as author_name
    FROM posts
    JOIN users ON posts.user_id = users.id
    WHERE posts.published = 1
    ORDER BY posts.created_at DESC
  '''),
  
  mapper: (map) => Post.fromMapWithAuthor(map),
  
  // Custom item builder with animations
  itemBuilder: (context, post) => AnimatedContainer(
    duration: Duration(milliseconds: 300),
    child: PostCard(post: post),
  ),
  
  // Separator between items
  separatorBuilder: (context, index) => Divider(height: 1),
  
  // Performance optimizations
  cacheExtent: 200, // Preload items outside viewport
  addAutomaticKeepAlives: true, // Keep items alive when scrolled out
  
  // Scroll behavior
  scrollDirection: Axis.vertical,
  reverse: false,
  shrinkWrap: false,
  
  // Pull to refresh
  onRefresh: () async {
    // Trigger manual refresh if needed
    // QueryListView automatically updates, but you can trigger additional actions
    await _syncWithServer();
  },
)
```

### ServerSyncManagerWidget

Manage background synchronization with remote servers:

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DatabaseProvider(
      schema: buildSchema,
      databaseName: 'app.db',
      child: ServerSyncManagerWidget(
        // Sync configuration
        fetchInterval: Duration(minutes: 5),
        retryStrategy: ExponentialBackoffRetryStrategy(
          initialDelay: Duration(seconds: 1),
          maxDelay: Duration(minutes: 5),
          maxRetries: 5,
        ),
        
        // Fetch data from server
        onFetch: _handleFetch,
        
        // Send local changes to server
        onSend: _handleSend,
        
        // Optional: Handle sync events
        onSyncStart: () => print('Sync started'),
        onSyncComplete: () => print('Sync completed'),
        onSyncError: (error) => print('Sync error: $error'),
        
        child: MainScreen(),
      ),
    );
  }
  
  Future<void> _handleFetch(DeclarativeDatabase database, String table, DateTime? lastSynced) async {
    // Fetch updates from your server
    final updates = await ApiClient.fetchUpdates(table, lastSynced);
    
    for (final update in updates) {
      await database.insert(table, update);
    }
  }
  
  Future<bool> _handleSend(List<DirtyRow> operations) async {
    try {
      // Send local changes to server
      final success = await ApiClient.sendChanges(operations);
      return success;
    } catch (e) {
      print('Failed to send changes: $e');
      return false;
    }
  }
}
```

## Practical Examples

### Master-Detail Pattern

```dart
// Master list screen
class PostListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Posts')),
      body: QueryListView<Post>(
        database: DatabaseProvider.of(context),
        query: (q) => q.from('posts').orderBy('created_at DESC'),
        mapper: Post.fromMap,
        itemBuilder: (context, post) => ListTile(
          title: Text(post.title),
          subtitle: Text(post.excerpt ?? ''),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PostDetailScreen(postId: post.id),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNewPost(context),
        child: Icon(Icons.add),
      ),
    );
  }
  
  void _createNewPost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePostScreen(),
      ),
    );
  }
}

// Detail screen with reactive updates
class PostDetailScreen extends StatelessWidget {
  final String postId;
  
  PostDetailScreen({required this.postId});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QueryListView<Post>(
        database: DatabaseProvider.of(context),
        query: (q) => q.from('posts').where('id = ?', [postId]),
        mapper: Post.fromMap,
        itemBuilder: (context, post) => PostDetailView(post: post),
        emptyBuilder: (context) => Center(
          child: Text('Post not found'),
        ),
      ),
    );
  }
}

class PostDetailView extends StatelessWidget {
  final Post post;
  
  PostDetailView({required this.post});
  
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Text(post.title),
          expandedHeight: 200,
          flexibleSpace: FlexibleSpaceBar(
            background: post.imageUrl != null
              ? Image.network(post.imageUrl!, fit: BoxFit.cover)
              : Container(color: Colors.grey),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.content,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                SizedBox(height: 32),
                Text(
                  'Comments',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: CommentList(postId: post.id),
        ),
      ],
    );
  }
}

// Comments list with its own reactive query
class CommentList extends StatelessWidget {
  final String postId;
  
  CommentList({required this.postId});
  
  @override
  Widget build(BuildContext context) {
    return QueryListView<Comment>(
      database: DatabaseProvider.of(context),
      query: (q) => q
        .from('comments')
        .where('post_id = ? AND approved = 1', [postId])
        .orderBy('created_at ASC'),
      mapper: Comment.fromMap,
      itemBuilder: (context, comment) => CommentCard(comment: comment),
      shrinkWrap: true, // Important for nested ListView
      physics: NeverScrollableScrollPhysics(), // Let parent handle scrolling
    );
  }
}
```

### Search and Filter Interface

```dart
class SearchableUserList extends StatefulWidget {
  @override
  _SearchableUserListState createState() => _SearchableUserListState();
}

class _SearchableUserListState extends State<SearchableUserList> {
  String _searchQuery = '';
  String _selectedRole = '';
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: InputDecoration(
            hintText: 'Search users...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: TextStyle(color: Colors.white),
          onChanged: (query) {
            setState(() {
              _searchQuery = query;
            });
          },
        ),
      ),
      body: Column(
        children: [
          // Filter controls
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Role: '),
                DropdownButton<String>(
                  value: _selectedRole.isEmpty ? null : _selectedRole,
                  hint: Text('All Roles'),
                  items: ['admin', 'user', 'moderator']
                    .map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(role),
                    ))
                    .toList(),
                  onChanged: (role) {
                    setState(() {
                      _selectedRole = role ?? '';
                    });
                  },
                ),
              ],
            ),
          ),
          
          // Filtered user list
          Expanded(
            child: QueryListView<User>(
              database: DatabaseProvider.of(context),
              query: (q) {
                var query = q.from('users');
                
                // Apply search filter
                if (_searchQuery.isNotEmpty) {
                  query = query.where(
                    'name LIKE ? OR email LIKE ?',
                    ['%$_searchQuery%', '%$_searchQuery%'],
                  );
                }
                
                // Apply role filter
                if (_selectedRole.isNotEmpty) {
                  query = query.where('role = ?', [_selectedRole]);
                }
                
                return query.orderBy('name ASC');
              },
              mapper: User.fromMap,
              itemBuilder: (context, user) => UserListTile(user: user),
              emptyBuilder: (context) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 64, color: Colors.grey),
                    Text('No users match your search'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

### Form Integration

```dart
class EditUserScreen extends StatefulWidget {
  final String userId;
  
  EditUserScreen({required this.userId});
  
  @override
  _EditUserScreenState createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit User'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _saveUser,
          ),
        ],
      ),
      body: QueryListView<User>(
        database: DatabaseProvider.of(context),
        query: (q) => q.from('users').where('id = ?', [widget.userId]),
        mapper: User.fromMap,
        itemBuilder: (context, user) {
          // Update form when user data changes
          if (_nameController.text != user.name) {
            _nameController.text = user.name;
          }
          if (_emailController.text != user.email) {
            _emailController.text = user.email;
          }
          
          return Form(
            key: _formKey,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(labelText: 'Name'),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Name is required';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(labelText: 'Email'),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Email is required';
                      }
                      if (!value!.contains('@')) {
                        return 'Invalid email';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  void _saveUser() async {
    if (_formKey.currentState?.validate() ?? false) {
      final database = DatabaseProvider.of(context);
      
      await database.update(
        'users',
        {
          'name': _nameController.text,
          'email': _emailController.text,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [widget.userId],
      );
      
      Navigator.pop(context);
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
```

## State Management Integration

### With Provider

```dart
// User service with reactive streams
class UserService extends ChangeNotifier {
  final DeclarativeDatabase _database;
  StreamSubscription<List<Map<String, Object?>>>? _subscription;
  List<User> _users = [];
  
  UserService(this._database) {
    _subscription = _database.streamQuery('users').listen((userData) {
      _users = userData.map((data) => User.fromMap(data)).toList();
      notifyListeners();
    });
  }
  
  List<User> get users => _users;
  
  Future<void> addUser(User user) async {
    await _database.insert('users', user.toMap());
    // Stream will automatically update _users
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

// Usage in app
MultiProvider(
  providers: [
    Provider<DeclarativeDatabase>(
      create: (context) => DeclarativeDatabase(
        schema: buildSchema,
        path: 'app.db',
      ),
    ),
    ChangeNotifierProvider<UserService>(
      create: (context) => UserService(
        Provider.of<DeclarativeDatabase>(context, listen: false),
      ),
    ),
  ],
  child: MyApp(),
)
```

### With Riverpod

```dart
// Database provider
final databaseProvider = Provider<DeclarativeDatabase>((ref) {
  return DeclarativeDatabase(
    schema: buildSchema,
    path: 'app.db',
  );
});

// Stream provider for users
final usersStreamProvider = StreamProvider<List<User>>((ref) {
  final database = ref.read(databaseProvider);
  return database
    .streamQuery('users')
    .map((userData) => userData.map((data) => User.fromMap(data)).toList());
});

// Usage in widgets
class UserListWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersStreamProvider);
    
    return usersAsync.when(
      data: (users) => ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) => UserTile(user: users[index]),
      ),
      loading: () => CircularProgressIndicator(),
      error: (error, stack) => Text('Error: $error'),
    );
  }
}
```

### With BLoC

```dart
// User events
abstract class UserEvent {}
class LoadUsers extends UserEvent {}
class AddUser extends UserEvent {
  final User user;
  AddUser(this.user);
}

// User state
abstract class UserState {}
class UserLoading extends UserState {}
class UserLoaded extends UserState {
  final List<User> users;
  UserLoaded(this.users);
}
class UserError extends UserState {
  final String message;
  UserError(this.message);
}

// User BLoC
class UserBloc extends Bloc<UserEvent, UserState> {
  final DeclarativeDatabase database;
  StreamSubscription<List<Map<String, Object?>>>? _subscription;
  
  UserBloc(this.database) : super(UserLoading()) {
    on<LoadUsers>(_onLoadUsers);
    on<AddUser>(_onAddUser);
  }
  
  void _onLoadUsers(LoadUsers event, Emitter<UserState> emit) {
    _subscription?.cancel();
    _subscription = database.streamQuery('users').listen(
      (userData) {
        final users = userData.map((data) => User.fromMap(data)).toList();
        emit(UserLoaded(users));
      },
      onError: (error) => emit(UserError(error.toString())),
    );
  }
  
  Future<void> _onAddUser(AddUser event, Emitter<UserState> emit) async {
    try {
      await database.insert('users', event.user.toMap());
      // Stream will automatically trigger update
    } catch (e) {
      emit(UserError(e.toString()));
    }
  }
  
  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
```

## Performance Optimization

### List Optimization

```dart
QueryListView<User>(
  database: DatabaseProvider.of(context),
  query: (q) => q.from('users'),
  mapper: User.fromMap,
  
  // Optimize list performance
  itemBuilder: (context, user) => UserTile(
    key: ValueKey(user.id), // Stable keys for efficient updates
    user: user,
  ),
  
  // ListView performance settings
  cacheExtent: 200, // Preload items outside viewport
  addAutomaticKeepAlives: true, // Keep items alive when scrolled out
  addRepaintBoundaries: true, // Optimize repainting
  
  // Custom scroll physics for better feel
  physics: BouncingScrollPhysics(),
)
```

### Memory Management

```dart
class OptimizedUserList extends StatefulWidget {
  @override
  _OptimizedUserListState createState() => _OptimizedUserListState();
}

class _OptimizedUserListState extends State<OptimizedUserList>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; // Keep widget state alive
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return QueryListView<User>(
      database: DatabaseProvider.of(context),
      query: (q) => q.from('users').limit(100), // Limit for performance
      mapper: User.fromMap,
      itemBuilder: (context, user) => UserTile(user: user),
    );
  }
}
```

## Best Practices

### Error Handling

```dart
class RobustUserList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return QueryListView<User>(
      database: DatabaseProvider.of(context),
      query: (q) => q.from('users'),
      mapper: User.fromMap,
      itemBuilder: (context, user) => UserTile(user: user),
      
      // Comprehensive error handling
      errorBuilder: (context, error) {
        // Log error for debugging
        print('User list error: $error');
        
        // Show user-friendly error
        return ErrorWidget(
          message: 'Unable to load users',
          onRetry: () {
            // Trigger rebuild
            (context as Element).markNeedsBuild();
          },
        );
      },
      
      // Handle empty state
      emptyBuilder: (context) => EmptyState(
        icon: Icons.people_outline,
        title: 'No users yet',
        subtitle: 'Add your first user to get started',
        action: ElevatedButton(
          onPressed: () => _showAddUserDialog(context),
          child: Text('Add User'),
        ),
      ),
    );
  }
}
```

### Accessibility

```dart
QueryListView<User>(
  database: DatabaseProvider.of(context),
  query: (q) => q.from('users'),
  mapper: User.fromMap,
  itemBuilder: (context, user) => Semantics(
    label: 'User ${user.name}',
    hint: 'Tap to view user details',
    child: UserTile(user: user),
  ),
  
  // Accessibility for loading state
  loadingBuilder: (context) => Semantics(
    label: 'Loading users',
    child: CircularProgressIndicator(),
  ),
)
```

## Next Steps

Now that you understand Flutter integration, explore the complete examples in the repository:

- **Core Library Example**: [`declarative_sqlite/example/`](https://github.com/graknol/declarative_sqlite/tree/main/declarative_sqlite/example)
- **Flutter Example**: [`declarative_sqlite_flutter/example/`](https://github.com/graknol/declarative_sqlite/tree/main/declarative_sqlite_flutter/example)