import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite/sqflite.dart';

/// Demo application showing the new sync status indicators in AutoForm
/// 
/// This demo shows:
/// 1. Field sync indicators that change from hollow circle (local) -> 
///    circle with tick (saved) -> filled circle with tick (synced)
/// 2. User attribution showing who made changes when synced from server
/// 3. Real-time status updates as data flows through the sync pipeline
/// 
/// Run this demo to see the sync indicators in action.
class SyncIndicatorDemo extends StatefulWidget {
  const SyncIndicatorDemo({Key? key}) : super(key: key);

  @override
  State<SyncIndicatorDemo> createState() => _SyncIndicatorDemoState();
}

class _SyncIndicatorDemoState extends State<SyncIndicatorDemo> {
  Database? database;
  DataAccess? dataAccess;
  ServerSyncManager? syncManager;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    try {
      // Create the schema for our demo
      final schema = SchemaBuilder()
          .table('users', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name')
              .text('email')
              .text('role')
              .integer('age'))
          .build();

      // Open in-memory database for demo
      database = await openDatabase(':memory:');
      
      // Migrate schema
      final migrator = SchemaMigrator();
      await migrator.migrate(database!, schema);

      // Create DataAccess with LWW support for sync tracking
      dataAccess = DataAccess(
        database: database!,
        schema: schema,
        enableLWW: true, // Required for sync tracking
      );

      // Create mock sync manager
      syncManager = ServerSyncManager(
        dataAccess: dataAccess!,
        uploadCallback: _mockServerUpload,
      );

      // Insert some demo data
      await _insertDemoData();

      setState(() {});
    } catch (e) {
      print('Demo initialization error: $e');
    }
  }

  Future<void> _insertDemoData() async {
    if (dataAccess == null) return;

    await dataAccess!.insert('users', {
      'name': 'John Doe',
      'email': 'john@example.com',
      'role': 'Developer',
      'age': 30,
    });

    await dataAccess!.insert('users', {
      'name': 'Jane Smith',
      'email': 'jane@example.com',
      'role': 'Designer',
      'age': 28,
    });
  }

  /// Mock server upload function that simulates server sync
  Future<bool> _mockServerUpload(List<PendingOperation> operations) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));
    
    // Simulate 90% success rate
    return DateTime.now().millisecondsSinceEpoch % 10 != 0;
  }

  @override
  Widget build(BuildContext context) {
    if (dataAccess == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return DataAccessProvider(
      dataAccess: dataAccess!,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sync Indicators Demo'),
          actions: [
            // Show sync status in app bar
            if (syncManager != null)
              SyncStatusWidget(
                syncManager: syncManager!,
                compact: true,
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Demo instructions
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync Indicators Demo',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Watch the sync indicators as you edit fields:',
                      ),
                      const SizedBox(height: 8),
                      _buildIndicatorLegend(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // User list with edit capabilities
              Expanded(
                child: ReactiveRecordListBuilder(
                  tableName: 'users',
                  itemBuilder: (context, recordData) => Card(
                    child: ListTile(
                      title: Text(recordData['name'] ?? ''),
                      subtitle: Text(recordData['email'] ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditDialog(recordData),
                      ),
                    ),
                  ),
                ),
              ),
              
              // Add new user button
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add New User'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndicatorLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.radio_button_unchecked, color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            const Text('Local changes (not saved)'),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.blue, size: 16),
            const SizedBox(width: 8),
            const Text('Saved to database'),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 16),
            const SizedBox(width: 8),
            const Text('Synced to server'),
          ],
        ),
      ],
    );
  }

  void _showEditDialog(Map<String, dynamic> recordData) {
    final query = QueryBuilder().selectAll().from('users');
    
    AutoFormDialog.showEdit(
      context: context,
      query: query,
      primaryKey: recordData['id'],
      title: 'Edit User',
      fields: [
        AutoFormField.text('name', 
          label: 'Full Name',
          required: true,
          showSyncIndicator: true),
        AutoFormField.text('email', 
          label: 'Email Address',
          showSyncIndicator: true),
        AutoFormField.text('role', 
          label: 'Job Role',
          showSyncIndicator: true),
        AutoFormField.text('age', 
          label: 'Age',
          showSyncIndicator: true),
      ],
    );
  }

  void _showCreateDialog() {
    final query = QueryBuilder().selectAll().from('users');
    
    AutoFormDialog.showCreate(
      context: context,
      query: query,
      title: 'Add New User',
      fields: [
        AutoFormField.text('name', 
          label: 'Full Name',
          required: true,
          showSyncIndicator: true),
        AutoFormField.text('email', 
          label: 'Email Address',
          showSyncIndicator: true),
        AutoFormField.text('role', 
          label: 'Job Role',
          showSyncIndicator: true),
        AutoFormField.text('age', 
          label: 'Age',
          showSyncIndicator: true),
      ],
    );
  }
}

/// Main app entry point for the demo
class SyncIndicatorDemoApp extends StatelessWidget {
  const SyncIndicatorDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sync Indicators Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SyncIndicatorDemo(),
    );
  }
}

void main() {
  runApp(const SyncIndicatorDemoApp());
}