import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Example showcasing all the new easy-to-use features added to the library:
/// - AutoForm for schema-based form generation
/// - SchemaInspector for visual database browsing
/// - Dashboard widgets for analytics
/// - DataAccessProvider for cleaner API
void main() async {
  // Initialize SQLite for desktop/testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Declarative SQLite Flutter - New Features Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DatabaseSetupPage(),
    );
  }
}

class DatabaseSetupPage extends StatefulWidget {
  const DatabaseSetupPage({super.key});

  @override
  State<DatabaseSetupPage> createState() => _DatabaseSetupPageState();
}

class _DatabaseSetupPageState extends State<DatabaseSetupPage> {
  DataAccess? _dataAccess;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupDatabase();
  }

  Future<void> _setupDatabase() async {
    try {
      // Create sample schema
      final schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .text('email', (col) => col.unique())
              .integer('age')
              .text('status', (col) => col.defaultValue('active'))
              .text('department')
              .timestamp('created_at', (col) => col.defaultValue('CURRENT_TIMESTAMP'))
              .index('idx_status', ['status'])
              .index('idx_department', ['department']))
          .table('orders', (table) => table
              .autoIncrementPrimaryKey('id')
              .integer('user_id', (col) => col.notNull())
              .text('product_name', (col) => col.notNull())
              .real('amount', (col) => col.notNull())
              .text('status', (col) => col.defaultValue('pending'))
              .timestamp('created_at', (col) => col.defaultValue('CURRENT_TIMESTAMP'))
              .foreignKey(['user_id'], 'users', ['id']))
          .table('tasks', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .text('description')
              .text('status', (col) => col.defaultValue('todo'))
              .integer('priority', (col) => col.defaultValue(1))
              .timestamp('created_at', (col) => col.defaultValue('CURRENT_TIMESTAMP'))
              .timestamp('due_date'))
          .build();

      // Setup database
      final database = await openDatabase(':memory:');
      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);

      // Create DataAccess instance
      final dataAccess = DataAccess(database: database, schema: schema);

      // Insert sample data
      await _insertSampleData(dataAccess);

      setState(() {
        _dataAccess = dataAccess;
        _isLoading = false;
      });
    } catch (e) {
      print('Error setting up database: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _insertSampleData(DataAccess dataAccess) async {
    // Insert sample users
    final userId1 = await dataAccess.insert('users', {
      'name': 'John Doe',
      'email': 'john@example.com',
      'age': 30,
      'status': 'active',
      'department': 'Engineering'
    });

    final userId2 = await dataAccess.insert('users', {
      'name': 'Jane Smith',
      'email': 'jane@example.com',
      'age': 28,
      'status': 'active',
      'department': 'Marketing'
    });

    await dataAccess.insert('users', {
      'name': 'Bob Wilson',
      'email': 'bob@example.com',
      'age': 35,
      'status': 'inactive',
      'department': 'Sales'
    });

    // Insert sample orders
    await dataAccess.insert('orders', {
      'user_id': userId1,
      'product_name': 'Laptop',
      'amount': 1299.99,
      'status': 'completed'
    });

    await dataAccess.insert('orders', {
      'user_id': userId2,
      'product_name': 'Mouse',
      'amount': 29.99,
      'status': 'pending'
    });

    await dataAccess.insert('orders', {
      'user_id': userId1,
      'product_name': 'Keyboard',
      'amount': 79.99,
      'status': 'shipped'
    });

    // Insert sample tasks
    await dataAccess.insert('tasks', {
      'title': 'Review code',
      'description': 'Review pull request #123',
      'status': 'in_progress',
      'priority': 2
    });

    await dataAccess.insert('tasks', {
      'title': 'Write documentation',
      'description': 'Update API documentation',
      'status': 'todo',
      'priority': 1
    });

    await dataAccess.insert('tasks', {
      'title': 'Fix bug',
      'description': 'Fix authentication issue',
      'status': 'done',
      'priority': 3
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Setting up database...'),
            ],
          ),
        ),
      );
    }

    if (_dataAccess == null) {
      return const Scaffold(
        body: Center(
          child: Text('Error setting up database'),
        ),
      );
    }

    // Wrap the entire app with DataAccessProvider for clean API
    return DataAccessProvider(
      dataAccess: _dataAccess!,
      child: const FeaturesShowcasePage(),
    );
  }
}

class FeaturesShowcasePage extends StatefulWidget {
  const FeaturesShowcasePage({super.key});

  @override
  State<FeaturesShowcasePage> createState() => _FeaturesShowcasePageState();
}

class _FeaturesShowcasePageState extends State<FeaturesShowcasePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const DashboardPage(),
    const AutoFormPage(),
    const SchemaInspectorPage(),
    const ReactiveWidgetsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Declarative SQLite Flutter - New Features'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note),
            label: 'Auto Forms',
          ),
          NavigationDestination(
            icon: Icon(Icons.storage),
            label: 'Schema Inspector',
          ),
          NavigationDestination(
            icon: Icon(Icons.widgets),
            label: 'Reactive Widgets',
          ),
        ],
      ),
    );
  }
}

// Dashboard page showcasing analytics widgets
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analytics Dashboard',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: DashboardGrid([
              DashboardWidgets.countCard(
                tableName: 'users',
                title: 'Total Users',
                subtitle: 'All registered users',
                icon: Icons.people,
                color: Colors.blue,
              ),
              DashboardWidgets.countCard(
                tableName: 'users',
                title: 'Active Users',
                subtitle: 'Currently active',
                where: 'status = ?',
                whereArgs: ['active'],
                icon: Icons.person_check,
                color: Colors.green,
              ),
              DashboardWidgets.countCard(
                tableName: 'orders',
                title: 'Total Orders',
                subtitle: 'All time',
                icon: Icons.shopping_cart,
                color: Colors.orange,
              ),
              DashboardWidgets.trendIndicator(
                tableName: 'orders',
                title: 'Orders Trend',
                dateColumn: 'created_at',
                period: const Duration(days: 30),
                icon: Icons.trending_up,
              ),
              DashboardWidgets.statusDistribution(
                tableName: 'orders',
                statusColumn: 'status',
                title: 'Order Status Distribution',
              ),
              DashboardWidgets.statusDistribution(
                tableName: 'tasks',
                statusColumn: 'status',
                title: 'Task Status Distribution',
              ),
              DashboardWidgets.summaryTable(
                tableName: 'users',
                title: 'Users by Department',
                aggregations: {'id': 'COUNT'},
                groupBy: 'department',
              ),
              DashboardWidgets.summaryTable(
                tableName: 'orders',
                title: 'Revenue by Status',
                aggregations: {'amount': 'SUM', 'id': 'COUNT'},
                groupBy: 'status',
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// Auto-form page showcasing automatic form generation
class AutoFormPage extends StatelessWidget {
  const AutoFormPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auto-Generated Forms',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Forms automatically generated from table schemas with validation',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateUserDialog(context),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add User'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateOrderDialog(context),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add Order'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateTaskDialog(context),
                  icon: const Icon(Icons.add_task),
                  label: const Text('Add Task'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Users',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ReactiveRecordListBuilder(
                        tableName: 'users',
                        orderBy: 'id DESC',
                        limit: 10,
                        itemBuilder: (context, recordData) => ListTile(
                          leading: CircleAvatar(
                            child: Text(recordData['name'][0].toUpperCase()),
                          ),
                          title: Text(recordData['name']),
                          subtitle: Text('${recordData['email']} • ${recordData['department']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(recordData['status']),
                                backgroundColor: recordData['status'] == 'active' 
                                  ? Colors.green[100] 
                                  : Colors.grey[300],
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _showEditUserDialog(context, recordData),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateUserDialog(BuildContext context) {
    AutoFormDialog.showCreate(
      context: context,
      tableName: 'users',
      title: 'Add New User',
      columnLabels: {
        'name': 'Full Name',
        'email': 'Email Address',
        'age': 'Age (years)',
        'status': 'Account Status',
        'department': 'Department',
      },
      customValidators: {
        'email': (value) {
          if (value != null && value.isNotEmpty && !value.contains('@')) {
            return 'Please enter a valid email address';
          }
          return null;
        },
        'age': (value) {
          if (value != null && value.isNotEmpty) {
            final age = int.tryParse(value);
            if (age == null || age < 0 || age > 120) {
              return 'Please enter a valid age (0-120)';
            }
          }
          return null;
        },
      },
      onSave: (data) async {
        try {
          final dataAccess = DataAccessProvider.of(context);
          await dataAccess.insert('users', data);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User created successfully!')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating user: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  void _showEditUserDialog(BuildContext context, RecordData recordData) {
    AutoFormDialog.showEdit(
      context: context,
      tableName: 'users',
      primaryKey: recordData.primaryKey,
      title: 'Edit User',
      columnLabels: {
        'name': 'Full Name',
        'email': 'Email Address',
        'age': 'Age (years)',
        'status': 'Account Status',
        'department': 'Department',
      },
      onSave: (data) async {
        try {
          await recordData.updateColumns(data);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User updated successfully!')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating user: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  void _showCreateOrderDialog(BuildContext context) {
    AutoFormDialog.showCreate(
      context: context,
      tableName: 'orders',
      title: 'Add New Order',
      columnLabels: {
        'user_id': 'User ID',
        'product_name': 'Product Name',
        'amount': 'Amount ($)',
        'status': 'Order Status',
      },
      onSave: (data) async {
        try {
          final dataAccess = DataAccessProvider.of(context);
          await dataAccess.insert('orders', data);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order created successfully!')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating order: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  void _showCreateTaskDialog(BuildContext context) {
    AutoFormDialog.showCreate(
      context: context,
      tableName: 'tasks',
      title: 'Add New Task',
      columnLabels: {
        'title': 'Task Title',
        'description': 'Description',
        'status': 'Status',
        'priority': 'Priority (1-5)',
      },
      onSave: (data) async {
        try {
          final dataAccess = DataAccessProvider.of(context);
          await dataAccess.insert('tasks', data);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task created successfully!')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating task: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }
}

// Schema inspector page showcasing database browsing
class SchemaInspectorPage extends StatelessWidget {
  const SchemaInspectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SchemaInspector(
      title: 'Database Schema & Data Browser',
      expandDataByDefault: true,
    );
  }
}

// Reactive widgets page showing the building blocks
class ReactiveWidgetsPage extends StatelessWidget {
  const ReactiveWidgetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reactive Widget Building Blocks',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Low-level reactive widgets for building custom components',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'List Builder', icon: Icon(Icons.list)),
                      Tab(text: 'Grid Builder', icon: Icon(Icons.grid_view)),
                      Tab(text: 'Single Record', icon: Icon(Icons.article)),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildListBuilderExample(),
                        _buildGridBuilderExample(),
                        _buildSingleRecordExample(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListBuilderExample() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'ReactiveRecordListBuilder Example\nEach item has access to CRUD operations',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ReactiveRecordListBuilder(
              tableName: 'tasks',
              orderBy: 'priority DESC, created_at DESC',
              itemBuilder: (context, recordData) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getPriorityColor(recordData['priority']),
                    child: Text(
                      recordData['priority'].toString(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(recordData['title']),
                  subtitle: Text(recordData['description'] ?? 'No description'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(recordData['status']),
                        backgroundColor: _getStatusColor(recordData['status']),
                      ),
                      PopupMenuButton(
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            child: const Text('Mark Done'),
                            onTap: () => recordData.updateColumn('status', 'done'),
                          ),
                          PopupMenuItem(
                            child: const Text('Delete'),
                            onTap: () => recordData.delete(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridBuilderExample() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'ReactiveRecordGridBuilder Example\nUsers displayed in a grid with edit/delete actions',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ReactiveRecordGridBuilder(
              tableName: 'users',
              crossAxisCount: 2,
              childAspectRatio: 0.8,
              itemBuilder: (context, recordData) => Card(
                margin: const EdgeInsets.all(8.0),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: recordData['status'] == 'active' ? Colors.green : Colors.grey,
                        child: Text(
                          recordData['name'][0].toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        recordData['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        recordData['email'],
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        recordData['department'] ?? 'No dept',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16),
                            onPressed: () {
                              // Toggle status as an example
                              final newStatus = recordData['status'] == 'active' ? 'inactive' : 'active';
                              recordData.updateColumn('status', newStatus);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                            onPressed: () => recordData.delete(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleRecordExample() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'ReactiveRecordBuilder Example\nWatch a single record and interact with it',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ReactiveRecordBuilder(
              tableName: 'users',
              primaryKey: 1, // Watch the first user
              builder: (context, recordData) {
                if (recordData == null) {
                  return const Center(child: Text('User not found'));
                }

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: recordData['status'] == 'active' ? Colors.green : Colors.grey,
                        child: Text(
                          recordData['name'][0].toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        recordData['name'],
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        recordData['email'],
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              _buildInfoRow('Age', recordData['age'].toString()),
                              _buildInfoRow('Department', recordData['department'] ?? 'Not specified'),
                              _buildInfoRow('Status', recordData['status']),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              final newStatus = recordData['status'] == 'active' ? 'inactive' : 'active';
                              recordData.updateColumn('status', newStatus);
                            },
                            icon: const Icon(Icons.toggle_on),
                            label: Text('Toggle Status'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              final newAge = (recordData['age'] ?? 25) + 1;
                              recordData.updateColumn('age', newAge);
                            },
                            icon: const Icon(Icons.cake),
                            label: Text('Birthday!'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Color _getPriorityColor(int? priority) {
    switch (priority) {
      case 1: return Colors.green;
      case 2: return Colors.blue;
      case 3: return Colors.orange;
      case 4: return Colors.red;
      case 5: return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'done': return Colors.green[100]!;
      case 'in_progress': return Colors.blue[100]!;
      case 'todo': return Colors.orange[100]!;
      default: return Colors.grey[100]!;
    }
  }
}