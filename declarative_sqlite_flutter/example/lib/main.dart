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
        enableLWW: true,
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
              Tab(text: 'Master-Detail', icon: Icon(Icons.list)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            UserListTab(dataAccess: service!.dataAccess!),
            AddUserTab(dataAccess: service.dataAccess!),
            MasterDetailTab(dataAccess: service.dataAccess!),
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

class MasterDetailTab extends StatelessWidget {
  final DataAccess dataAccess;

  const MasterDetailTab({super.key, required this.dataAccess});

  @override
  Widget build(BuildContext context) {
    return SimpleMasterDetailView(
      dataAccess: dataAccess,
      masterTable: 'users',
      detailTable: 'posts',
      foreignKeyColumn: 'user_id',
      masterSectionTitle: 'Users',
      detailSectionTitle: 'Posts',
      masterTitle: (user) => user['name'],
      masterSubtitle: (user) => user['email'],
      detailTitle: (post) => post['title'] ?? 'Untitled',
      detailSubtitle: (post) => 'Status: ${post['status']}',
    );
  }
}