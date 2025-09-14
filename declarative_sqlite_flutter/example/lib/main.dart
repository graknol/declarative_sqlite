import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Declarative SQLite Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: DatabaseServiceProvider(
        schema: _createSchema(),
        databaseName: 'demo.db',
        child: const HomePage(),
      ),
    );
  }

  SchemaBuilder _createSchema() {
    return SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('email', (col) => col.notNull().unique())
          .integer('age')
          .integer('active', (col) => col.withDefaultValue(1))
          .index('idx_email', ['email']))
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .text('content')
          .integer('user_id', (col) => col.notNull())
          .text('status', (col) => col.withDefaultValue('draft'))
          .index('idx_user_id', ['user_id']));
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DatabaseProvider.of(context);
    
    if (service?.dataAccess == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Declarative SQLite Flutter'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Users', icon: Icon(Icons.people)),
              Tab(text: 'Add User', icon: Icon(Icons.person_add)),
              Tab(text: 'Record Builder', icon: Icon(Icons.edit)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            UserListTab(dataAccess: service!.dataAccess!),
            AddUserTab(dataAccess: service.dataAccess!),
            RecordBuilderTab(dataAccess: service.dataAccess!),
          ],
        ),
      ),
    );
  }
}

class UserListTab extends StatelessWidget {
  final DataAccess dataAccess;

  const UserListTab({super.key, required this.dataAccess});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ReactiveWidgets.statusCard(
                  dataAccess: dataAccess,
                  tableName: 'users',
                  title: 'Total Users',
                  valueColumn: 'COUNT',
                  icon: Icons.people,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ReactiveWidgets.statusCard(
                  dataAccess: dataAccess,
                  tableName: 'users',
                  title: 'Active Users',
                  valueColumn: 'COUNT',
                  where: 'active = 1',
                  icon: Icons.person,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReactiveListView.builder(
            dataAccess: dataAccess,
            tableName: 'users',
            orderBy: 'name ASC',
            itemBuilder: (context, user) {
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(user['name'][0].toUpperCase()),
                  ),
                  title: Text(user['name']),
                  subtitle: Text('${user['email']} • Age: ${user['age'] ?? 'Unknown'}'),
                  trailing: Icon(
                    user['active'] == 1 ? Icons.check_circle : Icons.cancel,
                    color: user['active'] == 1 ? Colors.green : Colors.red,
                  ),
                  onTap: () {
                    _showUserDetails(context, user);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showUserDetails(BuildContext context, Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: ${user['email']}'),
            Text('Age: ${user['age'] ?? 'Unknown'}'),
            Text('Status: ${user['active'] == 1 ? 'Active' : 'Inactive'}'),
            Text('ID: ${user['id']}'),
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
}

class AddUserTab extends StatefulWidget {
  final DataAccess dataAccess;

  const AddUserTab({super.key, required this.dataAccess});

  @override
  State<AddUserTab> createState() => _AddUserTabState();
}

class _AddUserTabState extends State<AddUserTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  double _age = 25;
  bool _active = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add New User',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: WidgetHelpers.required<String>(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              validator: WidgetHelpers.combine([
                WidgetHelpers.required<String>(),
                WidgetHelpers.email(),
              ]),
            ),
            const SizedBox(height: 16),
            Text(
              'Age: ${_age.round()}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: _age,
              min: 0,
              max: 120,
              divisions: 120,
              onChanged: (value) {
                setState(() {
                  _age = value;
                });
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Active'),
              value: _active,
              onChanged: (value) {
                setState(() {
                  _active = value ?? true;
                });
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveUser,
                child: const Text('Save User'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await widget.dataAccess.insert('users', {
        'name': _nameController.text,
        'email': _emailController.text,
        'age': _age.round(),
        'active': _active ? 1 : 0,
      });

      if (mounted) {
        WidgetHelpers.showSuccessSnackBar(context, 'User saved successfully!');
        _nameController.clear();
        _emailController.clear();
        setState(() {
          _age = 25;
          _active = true;
        });
      }
    } catch (e) {
      if (mounted) {
        WidgetHelpers.showErrorSnackBar(context, 'Failed to save user: $e');
      }
    }
  }
}

class RecordBuilderTab extends StatefulWidget {
  final DataAccess dataAccess;

  const RecordBuilderTab({super.key, required this.dataAccess});

  @override
  State<RecordBuilderTab> createState() => _RecordBuilderTabState();
}

class _RecordBuilderTabState extends State<RecordBuilderTab> {
  int? _selectedUserId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // User selector section
        Expanded(
          flex: 1,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select a User to Edit',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ReactiveListView(
                    dataAccess: widget.dataAccess,
                    tableName: 'users',
                    itemBuilder: (context, user) {
                      final isSelected = _selectedUserId == user['id'];
                      return Card(
                        elevation: isSelected ? 8 : 1,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          title: Text(user['name'] ?? 'Unknown'),
                          subtitle: Text(user['email'] ?? ''),
                          trailing: Text('Age: ${user['age'] ?? 'N/A'}'),
                          onTap: () {
                            setState(() {
                              _selectedUserId = user['id'];
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Record builder section
        Expanded(
          flex: 1,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: _selectedUserId == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Select a user above to edit their details',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ReactiveRecordBuilder(
                    dataAccess: widget.dataAccess,
                    tableName: 'users',
                    primaryKey: _selectedUserId!,
                    builder: (context, recordData) {
                      if (recordData == null) {
                        return const Center(
                          child: Text('User not found'),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Edit User Details',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            
                            // Name field
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: recordData['name'] ?? '',
                                    decoration: const InputDecoration(
                                      labelText: 'Name',
                                      border: OutlineInputBorder(),
                                    ),
                                    onFieldSubmitted: (value) {
                                      recordData.updateColumn('name', value);
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.save),
                                  onPressed: () {
                                    // Show save confirmation
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Changes saved automatically'),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // Email field
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: recordData['email'] ?? '',
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      border: OutlineInputBorder(),
                                    ),
                                    onFieldSubmitted: (value) {
                                      recordData.updateColumn('email', value);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // Age slider
                            Text('Age: ${recordData['age'] ?? 0}'),
                            Slider(
                              value: (recordData['age'] ?? 0).toDouble(),
                              min: 0,
                              max: 120,
                              divisions: 120,
                              onChanged: (value) {
                                recordData.updateColumn('age', value.round());
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Action buttons
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {
                                    recordData.updateColumns({
                                      'name': 'Updated Name',
                                      'age': 25,
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Bulk update applied'),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.update),
                                  label: const Text('Bulk Update'),
                                ),
                                const SizedBox(width: 16),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete User'),
                                        content: const Text('Are you sure you want to delete this user?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    
                                    if (confirm == true) {
                                      await recordData.delete();
                                      setState(() {
                                        _selectedUserId = null;
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('User deleted'),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.delete),
                                  label: const Text('Delete'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}