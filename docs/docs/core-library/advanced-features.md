# Advanced Features

Explore advanced capabilities of Declarative SQLite including garbage collection, factory registry management, and other utility features.

## Fileset Garbage Collection

When files or filesets are deleted from the database but not properly cleaned up from disk storage, they become "orphaned". The garbage collection API helps identify and remove these orphaned items to maintain disk space efficiency.

### Overview

Fileset garbage collection operates at two levels:

1. **Fileset Level**: Remove entire fileset directories that have no corresponding database records
2. **File Level**: Remove individual files within filesets that have no corresponding database records

### Garbage Collect Filesets

Remove orphaned fileset directories:

```dart
// Clean up all orphaned filesets
final result = await db.files.garbageCollectFilesets();
print('Removed ${result} orphaned filesets');

// Preserve specific filesets even if they're not in the database
final result = await db.files.garbageCollectFilesets(
  additionalValidFilesets: ['temp_fileset', 'backup_fileset'],
);
print('Removed ${result} orphaned filesets (preserved temp and backup)');
```

#### How it works:

1. Scans the fileset storage directory for all existing fileset folders
2. Queries the database for all fileset references across all tables
3. Identifies filesets that exist on disk but have no database references
4. Optionally preserves filesets specified in `additionalValidFilesets`
5. Removes orphaned fileset directories and all their contents

### Garbage Collect Files in Fileset

Remove orphaned files within a specific fileset:

```dart
// Clean up orphaned files in a specific fileset
final result = await db.files.garbageCollectFilesInFileset('user-avatars-123');
print('Removed ${result} orphaned files from fileset');

// Preserve specific files even if they're not in the database
final result = await db.files.garbageCollectFilesInFileset(
  'user-avatars-123',
  additionalValidFiles: ['temp.jpg', 'backup.png'],
);
print('Removed ${result} orphaned files (preserved temp.jpg and backup.png)');
```

#### How it works:

1. Scans the specified fileset directory for all existing files
2. Queries the database for all file references within that fileset
3. Identifies files that exist on disk but have no database references
4. Optionally preserves files specified in `additionalValidFiles`
5. Removes orphaned files

### Comprehensive Garbage Collection

Perform both fileset and file-level garbage collection in one operation:

```dart
// Clean up everything
final result = await db.files.garbageCollectAll();
print('Cleaned up:');
print('- ${result['filesets']} orphaned filesets');
print('- ${result['files']} orphaned files');

// With preservation options
final result = await db.files.garbageCollectAll(
  additionalValidFilesets: ['temp_storage'],
  filesetSpecificOptions: {
    'user-avatars-123': ['temp.jpg', 'backup.png'],
    'user-documents-456': ['draft.pdf'],
  },
);
```

### Garbage Collection in Practice

#### Scheduled Cleanup

```dart
// Run garbage collection periodically
class DatabaseMaintenanceService {
  final DeclarativeDatabase db;
  Timer? _cleanupTimer;
  
  DatabaseMaintenanceService(this.db);
  
  void startPeriodicCleanup() {
    _cleanupTimer = Timer.periodic(Duration(hours: 24), (_) async {
      try {
        final result = await db.files.garbageCollectAll();
        print('Daily cleanup completed: ${result['filesets']} filesets, ${result['files']} files removed');
      } catch (e) {
        print('Cleanup failed: $e');
      }
    });
  }
  
  void stop() {
    _cleanupTimer?.cancel();
  }
}
```

#### Manual Cleanup UI

```dart
// Provide manual cleanup option to users
class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isCleaningUp = false;
  
  Future<void> _performCleanup() async {
    setState(() { _isCleaningUp = true; });
    
    try {
      final result = await DatabaseProvider.of(context).files.garbageCollectAll();
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Cleanup Complete'),
          content: Text('Removed ${result['filesets']} unused filesets and ${result['files']} unused files.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Cleanup Failed'),
          content: Text('Error during cleanup: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      setState(() { _isCleaningUp = false; });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: Text('Clean Up Unused Files'),
            subtitle: Text('Remove orphaned files and filesets'),
            trailing: _isCleaningUp 
              ? CircularProgressIndicator()
              : Icon(Icons.cleaning_services),
            onTap: _isCleaningUp ? null : _performCleanup,
          ),
        ],
      ),
    );
  }
}
```

## Factory Registry Management

The `RecordMapFactoryRegistry` eliminates the need for mapper parameters in query methods by registering typed factories once at application startup.

### Registration

Register all your record types during application initialization:

```dart
void main() {
  // Register typed record factories
  RecordMapFactoryRegistry.register<User>(User.fromMap);
  RecordMapFactoryRegistry.register<Post>(Post.fromMap);
  RecordMapFactoryRegistry.register<Comment>(Comment.fromMap);
  RecordMapFactoryRegistry.register<Category>(Category.fromMap);
  
  runApp(MyApp());
}
```

### Batch Registration

For applications with many record types:

```dart
void registerAllFactories() {
  final factories = <Type, Function>{
    User: User.fromMap,
    Post: Post.fromMap,
    Comment: Comment.fromMap,
    Category: Category.fromMap,
    Tag: Tag.fromMap,
    UserProfile: UserProfile.fromMap,
    // ... more types
  };
  
  for (final entry in factories.entries) {
    RecordMapFactoryRegistry.registerUnsafe(entry.key, entry.value);
  }
}
```

### Factory Validation

Ensure all required factories are registered:

```dart
void validateFactories() {
  final requiredTypes = [User, Post, Comment, Category];
  
  for (final type in requiredTypes) {
    if (!RecordMapFactoryRegistry.isRegistered(type)) {
      throw StateError('Factory for $type is not registered');
    }
  }
  
  print('All required factories are registered');
}
```

### Runtime Factory Management

```dart
// Check if a factory is registered
if (RecordMapFactoryRegistry.isRegistered<User>()) {
  final users = await db.queryTyped<User>((q) => q.from('users'));
} else {
  // Fall back to manual mapping
  final userMaps = await db.query('users');
  final users = userMaps.map((m) => User.fromMap(m, db)).toList();
}

// Unregister a factory (rarely needed)
RecordMapFactoryRegistry.unregister<User>();

// Clear all factories (for testing)
RecordMapFactoryRegistry.clear();
```

## Singleton HLC Clock

The Hybrid Logical Clock (HLC) provides causal ordering for database operations across your entire application. The singleton pattern ensures all database instances use the same clock for consistency.

### Automatic Usage

The HLC clock is used automatically for:

- Last-Write-Wins (LWW) column updates
- Conflict resolution during synchronization
- Causal ordering of operations

```dart
// HLC is used automatically when you save records
final user = await db.queryTyped<User>((q) => q.from('users').first());
user.name = 'Updated Name';
await user.save(); // HLC timestamp is automatically set for system_version

print(user.systemVersion); // HLC timestamp (e.g., "1699123456789-0-node123")
```

### Manual HLC Operations

For advanced use cases, you can access the HLC directly:

```dart
// Get current HLC timestamp
final hlc = HLClock.instance;
final timestamp = hlc.now();
print('Current HLC: $timestamp');

// Update HLC with external timestamp (for sync scenarios)
hlc.update('1699123456790-1-othernode');

// Get next timestamp
final nextTimestamp = hlc.now();
print('Next HLC: $nextTimestamp'); // Guaranteed to be greater than previous
```

### HLC in Custom Implementations

```dart
// Use HLC for custom timestamping needs
class EventLogger {
  final DeclarativeDatabase db;
  
  EventLogger(this.db);
  
  Future<void> logEvent(String eventType, Map<String, dynamic> data) async {
    await db.insert('event_log', {
      'id': Guid.newGuid().toString(),
      'event_type': eventType,
      'data': jsonEncode(data),
      'timestamp': HLClock.instance.now(), // Use HLC for causal ordering
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
```

## Database Lifecycle Management

### Connection Pooling

```dart
// Efficient database connection management
class DatabaseManager {
  static DeclarativeDatabase? _instance;
  
  static Future<DeclarativeDatabase> get instance async {
    if (_instance == null) {
      _instance = await DeclarativeDatabase.open(
        'my_app.db',
        buildSchema,
        enableLogging: false, // Disable in production
      );
    }
    return _instance!;
  }
  
  static Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }
}
```

### Database Migration Validation

```dart
// Validate schema after opening database
Future<void> validateDatabaseSchema(DeclarativeDatabase db) async {
  // Check that required tables exist
  final tables = await db.query("SELECT name FROM sqlite_master WHERE type='table'");
  final tableNames = tables.map((t) => t['name'] as String).toSet();
  
  final requiredTables = {'users', 'posts', 'comments', 'categories'};
  final missingTables = requiredTables.difference(tableNames);
  
  if (missingTables.isNotEmpty) {
    throw StateError('Missing required tables: ${missingTables.join(', ')}');
  }
  
  // Check that required columns exist
  for (final tableName in requiredTables) {
    final columns = await db.query("PRAGMA table_info($tableName)");
    final columnNames = columns.map((c) => c['name'] as String).toSet();
    
    // Validate required columns per table
    switch (tableName) {
      case 'users':
        final required = {'id', 'name', 'email', 'system_id', 'system_version'};
        final missing = required.difference(columnNames);
        if (missing.isNotEmpty) {
          throw StateError('Table $tableName missing columns: ${missing.join(', ')}');
        }
        break;
      // ... validate other tables
    }
  }
  
  print('Database schema validation passed');
}
```

### Database Backup and Restore

```dart
// Simple database backup
class DatabaseBackupService {
  final DeclarativeDatabase db;
  
  DatabaseBackupService(this.db);
  
  Future<String> createBackup() async {
    final backupPath = 'backup_${DateTime.now().millisecondsSinceEpoch}.db';
    
    // SQLite backup using VACUUM INTO
    await db.execute('VACUUM INTO ?', [backupPath]);
    
    return backupPath;
  }
  
  Future<void> restoreFromBackup(String backupPath) async {
    // Close current database
    await db.close();
    
    // Replace current database file with backup
    final dbFile = File(db.path);
    final backupFile = File(backupPath);
    
    if (await backupFile.exists()) {
      await backupFile.copy(dbFile.path);
      print('Database restored from $backupPath');
    } else {
      throw FileSystemException('Backup file not found', backupPath);
    }
    
    // Reopen database
    // Note: You'd need to recreate the database instance
  }
}
```

## Performance Optimization

### Query Performance Monitoring

```dart
// Monitor query performance
class QueryPerformanceMonitor {
  static void logSlowQuery(String sql, List<dynamic> params, Duration duration) {
    if (duration.inMilliseconds > 100) { // Log queries taking more than 100ms
      print('SLOW QUERY (${duration.inMilliseconds}ms): $sql');
      if (params.isNotEmpty) {
        print('Parameters: $params');
      }
    }
  }
}

// Custom database wrapper with performance monitoring
class MonitoredDatabase {
  final DeclarativeDatabase _db;
  
  MonitoredDatabase(this._db);
  
  Future<List<Map<String, Object?>>> query(String sql, [List<dynamic>? params]) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _db.query(sql, params);
      return result;
    } finally {
      stopwatch.stop();
      QueryPerformanceMonitor.logSlowQuery(sql, params ?? [], stopwatch.elapsed);
    }
  }
}
```

### Index Management

```dart
// Create performance indexes
Future<void> createPerformanceIndexes(DeclarativeDatabase db) async {
  // Indexes for common query patterns
  await db.execute('CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id)');
  
  // Composite indexes for complex queries
  await db.execute('CREATE INDEX IF NOT EXISTS idx_posts_user_date ON posts(user_id, created_at)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_users_active_email ON users(active, email) WHERE active = 1');
  
  print('Performance indexes created');
}
```

## Error Recovery

### Automatic Error Recovery

```dart
// Implement automatic recovery for common issues
class DatabaseErrorRecovery {
  static Future<T> withRetry<T>(Future<T> Function() operation, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } on DbException catch (e) {
        if (attempt == maxRetries) rethrow;
        
        switch (e.errorCategory) {
          case DbErrorCategory.resourceExhausted:
          case DbErrorCategory.timeout:
            // Retry with exponential backoff
            await Future.delayed(Duration(milliseconds: 100 * attempt));
            continue;
          default:
            rethrow; // Don't retry for other error types
        }
      }
    }
    throw StateError('Unreachable');
  }
}

// Usage
final users = await DatabaseErrorRecovery.withRetry(() => 
  db.queryTyped<User>((q) => q.from('users'))
);
```

## Best Practices

### 1. Register Factories Early

```dart
// ✅ Good: Register in main() before any database operations
void main() {
  RecordMapFactoryRegistry.register<User>(User.fromMap);
  RecordMapFactoryRegistry.register<Post>(Post.fromMap);
  runApp(MyApp());
}
```

### 2. Schedule Regular Garbage Collection

```dart
// ✅ Good: Regular cleanup prevents disk bloat
Timer.periodic(Duration(days: 1), (_) async {
  try {
    await db.files.garbageCollectAll();
  } catch (e) {
    print('Cleanup failed: $e');
  }
});
```

### 3. Monitor Database Performance

```dart
// ✅ Good: Monitor and log performance issues
if (kDebugMode) {
  // Enable query logging in debug mode
  database.enableLogging = true;
}
```

## Next Steps

Now that you understand advanced features, explore:

- [Streaming Queries](streaming-queries) - Real-time data updates
- [Flutter Integration](../flutter-integration/widgets) - Reactive UI components
- [Database Operations](database-operations) - Core CRUD operations