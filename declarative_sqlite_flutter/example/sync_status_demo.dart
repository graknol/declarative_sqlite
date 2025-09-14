import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  runApp(SyncStatusDemo());
}

class SyncStatusDemo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sync Status Widget Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: SyncStatusDemoPage(),
    );
  }
}

class SyncStatusDemoPage extends StatefulWidget {
  @override
  _SyncStatusDemoPageState createState() => _SyncStatusDemoPageState();
}

class _SyncStatusDemoPageState extends State<SyncStatusDemoPage> {
  late Database database;
  late DataAccess dataAccess;
  late ServerSyncManager syncManager;
  bool _initialized = false;
  
  // Simulate different server responses
  int _callCount = 0;
  bool _simulateServerErrors = false;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    // Create in-memory database with LWW support
    database = await openDatabase(':memory:');
    
    final schema = SchemaBuilder()
      .table('notes', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull().lww())
          .text('content', (col) => col.lww())
          .text('category', (col) => col.lww())
          .integer('priority', (col) => col.lww()));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);
    
    dataAccess = await DataAccess.create(
      database: database,
      schema: schema,
    );

    // Create sync manager with simulated server behavior
    syncManager = ServerSyncManager(
      dataAccess: dataAccess,
      uploadCallback: _simulateServerUpload,
      onSyncStatus: (result) {
        print('Sync completed: ${result.syncedOperations.length} synced, '
              '${result.failedOperations.length} failed, '
              '${result.discardedOperations.length} discarded');
      },
      options: ServerSyncOptions(
        retryAttempts: 2,
        retryDelay: Duration(seconds: 1),
        batchSize: 3,
        syncInterval: Duration(seconds: 10),
      ),
    );

    // Start auto-sync
    await syncManager.startAutoSync();

    setState(() {
      _initialized = true;
    });
  }

  /// Simulates server upload with different response scenarios
  Future<bool> _simulateServerUpload(List<PendingOperation> operations) async {
    _callCount++;
    
    if (!_simulateServerErrors) {
      // Normal successful upload
      await Future.delayed(Duration(milliseconds: 500)); // Simulate network delay
      return true;
    }
    
    // Simulate different error scenarios
    if (_callCount % 4 == 1) {
      // 25% of calls: Permanent failure (400-like error)
      await Future.delayed(Duration(milliseconds: 200));
      return false; // This will discard the operations
    } else if (_callCount % 4 == 2) {
      // 25% of calls: Temporary failure (network error)
      await Future.delayed(Duration(milliseconds: 300));
      throw Exception('Network timeout');
    } else {
      // 50% of calls: Success
      await Future.delayed(Duration(milliseconds: 400));
      return true;
    }
  }

  @override
  void dispose() {
    syncManager.dispose();
    database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Sync Status Widget Demo'),
        actions: [
          IconButton(
            icon: Icon(Icons.debug_symbol),
            onPressed: () => _showSyncDebugPage(),
            tooltip: 'Debug Page',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact sync status widget
            Text(
              'Compact Sync Status:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            SyncStatusWidget(
              syncManager: syncManager,
              compact: true,
            ),
            
            SizedBox(height: 24),
            
            // Control panel
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Test Controls',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 12),
                    
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _addRandomNote,
                          child: Text('Add Note'),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _updateRandomNote,
                          child: Text('Update Note'),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _triggerManualSync,
                          child: Text('Manual Sync'),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: 12),
                    
                    SwitchListTile(
                      title: Text('Simulate Server Errors'),
                      subtitle: Text('Mix of permanent failures, temporary failures, and success'),
                      value: _simulateServerErrors,
                      onChanged: (value) {
                        setState(() {
                          _simulateServerErrors = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 24),
            
            // Recent notes list
            Text(
              'Recent Notes:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            Expanded(
              child: _buildNotesList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: dataAccess.getAll('notes'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final notes = snapshot.data ?? [];
        
        if (notes.isEmpty) {
          return Center(
            child: Text('No notes yet. Add some notes to test sync functionality.'),
          );
        }
        
        return ListView.builder(
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            return Card(
              child: ListTile(
                title: Text(note['title'] ?? 'Untitled'),
                subtitle: Text(note['content'] ?? ''),
                trailing: Chip(
                  label: Text(note['category'] ?? 'General'),
                  backgroundColor: _getCategoryColor(note['category']),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Work':
        return Colors.blue.withOpacity(0.3);
      case 'Personal':
        return Colors.green.withOpacity(0.3);
      case 'Important':
        return Colors.red.withOpacity(0.3);
      default:
        return Colors.grey.withOpacity(0.3);
    }
  }

  void _showSyncDebugPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SyncDebugPage(syncManager: syncManager),
      ),
    );
  }

  Future<void> _addRandomNote() async {
    final categories = ['Work', 'Personal', 'Important', 'General'];
    final titles = [
      'Meeting notes',
      'Project ideas',
      'Shopping list',
      'Important reminder',
      'Task to complete',
      'Random thought',
    ];
    final contents = [
      'This is a sample note content.',
      'Another note with different content.',
      'Important information here.',
      'Just a quick reminder.',
      'Detailed note with lots of information.',
      'Short note.',
    ];

    final random = DateTime.now().millisecondsSinceEpoch % 100;
    final id = await dataAccess.insert('notes', {
      'title': titles[random % titles.length],
      'content': contents[random % contents.length],
      'category': categories[random % categories.length],
      'priority': (random % 5) + 1,
    });

    // Create a pending operation by updating an LWW column
    await dataAccess.updateLWWColumn('notes', id, 'title', 
        '${titles[random % titles.length]} (Updated)');

    setState(() {}); // Refresh the UI
  }

  Future<void> _updateRandomNote() async {
    final notes = await dataAccess.getAll('notes');
    if (notes.isEmpty) return;

    final random = DateTime.now().millisecondsSinceEpoch % notes.length;
    final note = notes[random];
    
    // Update a random LWW column
    final updateFields = ['title', 'content', 'category'];
    final fieldToUpdate = updateFields[DateTime.now().millisecondsSinceEpoch % 3];
    final newValue = '${note[fieldToUpdate]} (Updated ${DateTime.now().millisecond})';
    
    await dataAccess.updateLWWColumn('notes', note['id'], fieldToUpdate, newValue);
    
    setState(() {}); // Refresh the UI
  }

  Future<void> _triggerManualSync() async {
    try {
      await syncManager.syncNow();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manual sync completed')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    }
  }
}

/// Debug page showing full sync status information
class SyncDebugPage extends StatelessWidget {
  final ServerSyncManager syncManager;

  const SyncDebugPage({Key? key, required this.syncManager}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sync Debug Page'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SyncStatusWidget(
          syncManager: syncManager,
          refreshInterval: Duration(seconds: 2), // Fast refresh for demo
          maxEventsToShow: 50,
          showPendingOperations: true,
          showSyncHistory: true,
          compact: false,
        ),
      ),
    );
  }
}