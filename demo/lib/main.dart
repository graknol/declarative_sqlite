import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  runApp(const DeclarativeSqliteDemo());
}

class DeclarativeSqliteDemo extends StatelessWidget {
  const DeclarativeSqliteDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Declarative SQLite Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: DatabaseProvider(
        schema: _buildDatabaseSchema,
        databaseName: 'demo.db',
        child: const DemoHomeScreen(),
      ),
    );
  }

  void _buildDatabaseSchema(SchemaBuilder builder) {
    // Users table
    builder.table('users', (table) {
      table.guid('id').notNull('');
      table.text('name').notNull('');
      table.text('email').notNull('');
      table.integer('age').notNull(0);
      table.date('created_at').notNull('');
      table.key(['id']).primary();
    });

    // Posts table
    builder.table('posts', (table) {
      table.guid('id').notNull('');
      table.guid('user_id').notNull('');
      table.text('title').notNull('');
      table.text('content').notNull('');
      table.date('created_at').notNull('');
      table.text('user_name').notNull(''); // Denormalized for demo simplicity
      table.key(['id']).primary();
    });
  }
}

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
}

class Post {
  final String id;
  final String userId;
  final String title;
  final String content;
  final String userName;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.userName,
    required this.createdAt,
  });

  static Post fromMap(Map<String, Object?> map) {
    return Post(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      userName: map['user_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class DemoHomeScreen extends StatefulWidget {
  const DemoHomeScreen({super.key});

  @override
  State<DemoHomeScreen> createState() => _DemoHomeScreenState();
}

class _DemoHomeScreenState extends State<DemoHomeScreen> {
  bool _showPostsOnly = false;
  String _currentFilter = 'all'; // 'all', 'young', 'old'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Declarative SQLite Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          _buildControlPanel(),
          Expanded(
            child: _showPostsOnly ? _buildPostsList() : _buildUsersList(),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _addSampleUser,
            heroTag: "addUser",
            icon: const Icon(Icons.person_add),
            label: const Text('Add User'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            onPressed: _addSamplePost,
            heroTag: "addPost",
            icon: const Icon(Icons.add_comment),
            label: const Text('Add Post'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Demo Controls',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All Users')),
                    ButtonSegment(value: 'young', label: Text('Young (≤25)')),
                    ButtonSegment(value: 'old', label: Text('Older (>25)')),
                  ],
                  selected: {_currentFilter},
                  onSelectionChanged: (Set<String> selection) {
                    setState(() {
                      _currentFilter = selection.first;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  title: const Text('Show Posts Instead'),
                  value: _showPostsOnly,
                  onChanged: (value) {
                    setState(() {
                      _showPostsOnly = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _updateRandomUser,
                child: const Text('Update Random User Age'),
              ),
              ElevatedButton(
                onPressed: _updateUserOutsideFilter,
                child: const Text('Update User (Outside Filter)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    return QueryListView<User>(
      database: DatabaseProvider.of(context),
      query: (q) {
        q.from('users');
        
        // Apply age filter based on current selection
        switch (_currentFilter) {
          case 'young':
            q.where(col('age').lte(25));
            break;
          case 'old':
            q.where(col('age').gt(25));
            break;
          case 'all':
          default:
            // No filter
            break;
        }
        
        q.orderBy(['created_at DESC']);
      },
      mapper: User.fromMap,
      loadingBuilder: (context) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading users...'),
          ],
        ),
      ),
      errorBuilder: (context, error) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error: $error',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      itemBuilder: (context, user) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue,
            child: Text(
              user.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(user.name),
          subtitle: Text('${user.email} • Age: ${user.age}'),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editUser(user),
          ),
          onTap: () => _showUserDetails(user),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 160), // Account for FABs
    );
  }

  Widget _buildPostsList() {
    return QueryListView<Post>(
      database: DatabaseProvider.of(context),
      query: (q) => q.from('posts').orderBy(['created_at DESC']),
      mapper: Post.fromMap,
      loadingBuilder: (context) => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading posts...'),
          ],
        ),
      ),
      errorBuilder: (context, error) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error: $error',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      itemBuilder: (context, post) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      post.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    'by ${post.userName}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(post.content),
              const SizedBox(height: 8),
              Text(
                'Posted ${_formatDate(post.createdAt)}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 160), // Account for FABs
    );
  }

  Future<void> _addSampleUser() async {
    final db = DatabaseProvider.of(context);
    final now = DateTime.now();
    
    // Generate a random user
    final names = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Henry'];
    final domains = ['gmail.com', 'yahoo.com', 'example.com', 'test.org'];
    
    final name = names[DateTime.now().millisecond % names.length];
    final domain = domains[DateTime.now().microsecond % domains.length];
    final age = 18 + (DateTime.now().millisecond % 40); // Age between 18-57
    
    await db.insert('users', {
      'id': _generateGuid(),
      'name': '$name ${DateTime.now().millisecond}',
      'email': '${name.toLowerCase()}${DateTime.now().millisecond}@$domain',
      'age': age,
      'created_at': now.toIso8601String(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added user: $name (Age: $age)')),
      );
    }
  }

  Future<void> _addSamplePost() async {
    final db = DatabaseProvider.of(context);
    
    // First, get a random user
    final users = await db.rawQuery('SELECT * FROM users LIMIT 10');
    if (users.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add some users first!')),
        );
      }
      return;
    }
    
    final randomUser = users[DateTime.now().millisecond % users.length];
    final now = DateTime.now();
    
    final postTitles = [
      'My thoughts on Flutter',
      'Learning SQLite',
      'Declarative programming rocks!',
      'Building better apps',
      'Database design patterns',
    ];
    
    final postContents = [
      'Flutter makes mobile development so much easier!',
      'Working with databases can be fun when done right.',
      'Declarative approaches lead to cleaner, more maintainable code.',
      'Always thinking about user experience first.',
      'Good database design is crucial for app performance.',
    ];
    
    final title = postTitles[DateTime.now().millisecond % postTitles.length];
    final content = postContents[DateTime.now().microsecond % postContents.length];
    
    await db.insert('posts', {
      'id': _generateGuid(),
      'user_id': randomUser['id'],
      'title': '$title ${DateTime.now().millisecond}',
      'content': content,
      'user_name': randomUser['name'],
      'created_at': now.toIso8601String(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added post: "$title" by ${randomUser['name']}')),
      );
    }
  }

  Future<void> _updateRandomUser() async {
    final db = DatabaseProvider.of(context);
    
    // Get users in current filter
    var query = 'SELECT * FROM users';
    var whereArgs = <Object?>[];
    
    switch (_currentFilter) {
      case 'young':
        query += ' WHERE age <= 25';
        break;
      case 'old':
        query += ' WHERE age > 25';
        break;
    }
    
    final users = await db.rawQuery(query, whereArgs);
    
    if (users.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No users found in current filter!')),
        );
      }
      return;
    }
    
    final randomUser = users[DateTime.now().millisecond % users.length];
    final newAge = 20 + (DateTime.now().millisecond % 30); // Age between 20-49
    
    await db.update(
      'users',
      {'age': newAge},
      where: 'id = ?',
      whereArgs: [randomUser['id']],
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${randomUser['name']} age to $newAge (was ${randomUser['age']})',
          ),
        ),
      );
    }
  }

  Future<void> _updateUserOutsideFilter() async {
    final db = DatabaseProvider.of(context);
    
    // Get users NOT in current filter
    var query = 'SELECT * FROM users';
    
    switch (_currentFilter) {
      case 'young':
        query += ' WHERE age > 25'; // Get older users when filter is young
        break;
      case 'old':
        query += ' WHERE age <= 25'; // Get younger users when filter is old
        break;
      case 'all':
        // When showing all, update someone to be very old (outside typical range)
        query += ' WHERE age < 60';
        break;
    }
    
    final users = await db.rawQuery(query);
    
    if (users.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No users found outside current filter!')),
        );
      }
      return;
    }
    
    final randomUser = users[DateTime.now().millisecond % users.length];
    
    // Update age to something that will move them outside current filter
    int newAge;
    switch (_currentFilter) {
      case 'young':
        newAge = 30 + (DateTime.now().millisecond % 20); // Make them older
        break;
      case 'old':
        newAge = 20 + (DateTime.now().millisecond % 5); // Make them younger
        break;
      case 'all':
      default:
        newAge = 65; // Very old
        break;
    }
    
    await db.update(
      'users',
      {'age': newAge},
      where: 'id = ?',
      whereArgs: [randomUser['id']],
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${randomUser['name']} age to $newAge (outside current filter) - they should disappear from the list!',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _editUser(User user) {
    // Show a simple dialog to edit user age
    showDialog(
      context: context,
      builder: (context) => _EditUserDialog(user: user),
    );
  }

  void _showUserDetails(User user) {
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
            Text('Created: ${_formatDate(user.createdAt)}'),
            Text('ID: ${user.id}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _generateGuid() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = (now * 1000 + DateTime.now().microsecond) % 1000000;
    return 'guid_${now}_$random';
  }
}

class _EditUserDialog extends StatefulWidget {
  final User user;

  const _EditUserDialog({required this.user});

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late TextEditingController _nameController;
  late TextEditingController _ageController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _ageController = TextEditingController(text: widget.user.age.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit User'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ageController,
            decoration: const InputDecoration(labelText: 'Age'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveChanges,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _saveChanges() async {
    final name = _nameController.text.trim();
    final ageText = _ageController.text.trim();
    
    if (name.isEmpty || ageText.isEmpty) {
      return;
    }
    
    final age = int.tryParse(ageText);
    if (age == null || age < 0 || age > 120) {
      return;
    }
    
    final db = DatabaseProvider.of(context);
    await db.update(
      'users',
      {
        'name': name,
        'age': age,
      },
      where: 'id = ?',
      whereArgs: [widget.user.id],
    );
    
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated ${widget.user.name}')),
      );
    }
  }
}
