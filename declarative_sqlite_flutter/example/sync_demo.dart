import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  runApp(const SyncDemoApp());
}

class SyncDemoApp extends StatelessWidget {
  const SyncDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Declarative SQLite Sync Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: DatabaseProvider(
        schema: (builder) {
          builder.table('users', (table) {
            table.guid('id').notNull();
            table.text('name').notNull();
            table.text('email').notNull();
            table.date('created_at').notNull();
            table.key(['id']).primary();
          });
        },
        databaseName: 'sync_demo.db',
        child: ServerSyncManagerWidget(
          retryStrategy: null, // Could use exponential backoff
          fetchInterval: const Duration(minutes: 2),
          onFetch: (database, table, lastSynced) async {
            // Simulate fetching data from server
            print('Fetching data for table: $table since $lastSynced');
            
            // In a real app, you would make HTTP requests here
            // await apiClient.fetchUsers(lastSynced);
            
            // Simulate adding some data
            if (table == 'users') {
              await database.insert('users', {
                'id': 'server-${DateTime.now().millisecondsSinceEpoch}',
                'name': 'Server User ${DateTime.now().second}',
                'email': 'server${DateTime.now().second}@example.com',
                'created_at': DateTime.now().toIso8601String(),
              });
            }
          },
          onSend: (operations) async {
            // Simulate sending changes to server
            print('Sending ${operations.length} operations to server');
            
            for (final operation in operations) {
              print('Operation: ${operation.operation} on ${operation.tableName}');
            }
            
            // In a real app, you would make HTTP requests here
            // final success = await apiClient.sendChanges(operations);
            
            // Simulate success
            return true;
          },
          child: const UserListScreen(),
        ),
      ),
    );
  }
}

class UserListScreen extends StatelessWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users (with Sync)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sync is running automatically every 2 minutes'),
                ),
              );
            },
          ),
        ],
      ),
      body: QueryListView<User>(
        database: DatabaseProvider.of(context),
        query: (q) => q.from('users').orderBy('created_at', descending: true),
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
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?'),
            ),
            title: Text(user.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.email),
                Text(
                  'Created: ${_formatDate(user.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteUser(context, user),
            ),
          ),
        ),
        // ListView properties
        padding: const EdgeInsets.all(8.0),
        physics: const BouncingScrollPhysics(),
        shrinkWrap: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addUser(context),
        child: const Icon(Icons.person_add),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addUser(BuildContext context) async {
    final db = DatabaseProvider.of(context);
    final timestamp = DateTime.now();
    
    await db.insert('users', {
      'id': 'local-${timestamp.millisecondsSinceEpoch}',
      'name': 'Local User ${timestamp.second}',
      'email': 'local${timestamp.second}@example.com',
      'created_at': timestamp.toIso8601String(),
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User added! Changes will sync automatically.'),
        ),
      );
    }
  }

  Future<void> _deleteUser(BuildContext context, User user) async {
    final db = DatabaseProvider.of(context);
    
    await db.delete('users', where: 'id = ?', whereArgs: [user.id]);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.name} deleted! Changes will sync automatically.'),
        ),
      );
    }
  }
}

/// Example data model for users
class User {
  final String id;
  final String name;
  final String email;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
  });

  static User fromMap(Map<String, Object?> map) {
    return User(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'created_at': createdAt.toIso8601String(),
    };
  }
}