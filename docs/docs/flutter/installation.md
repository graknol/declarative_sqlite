---
sidebar_position: 1
---

# Installation

Get started with the Flutter-specific integration package for Declarative SQLite.

## Prerequisites

- **Flutter SDK**: 3.10.0 or later
- **Dart SDK**: 3.5.3 or later
- Core `declarative_sqlite` package installed

## Installation

### 1. Add Dependencies

Add both the core library and Flutter integration to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  declarative_sqlite: ^1.0.1
  declarative_sqlite_flutter: ^1.0.0
  # SQLite implementation for Flutter
  sqflite: ^2.3.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  # Optional: Code generation
  declarative_sqlite_generator: ^1.0.0
  build_runner: ^2.4.7
```

### 2. Install Packages

```bash
flutter pub get
```

### 3. Import the Library

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
```

## Platform Support

The Flutter package automatically works on all Flutter platforms:

- ✅ **iOS** - Uses sqflite
- ✅ **Android** - Uses sqflite  
- ✅ **macOS** - Uses sqflite_common_ffi
- ✅ **Windows** - Uses sqflite_common_ffi
- ✅ **Linux** - Uses sqflite_common_ffi
- ✅ **Web** - Uses sql.js (via sqflite_web)

No additional platform-specific setup is required!

## Basic Setup

### 1. Create Your Schema

```dart
// lib/database/schema.dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final appSchema = SchemaBuilder()
  .table('users', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('username', (col) => col.notNull().unique())
    .text('email', (col) => col.notNull())
    .text('full_name')
    .boolean('is_active', (col) => col.notNull().defaultValue(true))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now())))
  .table('posts', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('title', (col) => col.notNull())
    .text('content', (col) => col.notNull())
    .integer('user_id', (col) => col.notNull())
    .boolean('published', (col) => col.notNull().defaultValue(false))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .foreignKey('user_id').references('users', 'id'));
```

### 2. Initialize Database

```dart
// lib/database/database.dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'schema.dart';

class AppDatabase {
  static DeclarativeDatabase? _instance;
  
  static Future<DeclarativeDatabase> get instance async {
    if (_instance == null) {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, 'app.db');
      
      _instance = await DeclarativeDatabase.init(
        path: path,
        schema: appSchema,
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

### 3. Database Provider

```dart
// lib/providers/database_provider.dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import '../database/database.dart';

class DatabaseProvider extends InheritedWidget {
  final DeclarativeDatabase database;
  
  const DatabaseProvider({
    Key? key,
    required this.database,
    required Widget child,
  }) : super(key: key, child: child);
  
  static DeclarativeDatabase of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<DatabaseProvider>();
    if (provider == null) {
      throw FlutterError('DatabaseProvider not found in widget tree');
    }
    return provider.database;
  }
  
  @override
  bool updateShouldNotify(DatabaseProvider oldWidget) {
    return database != oldWidget.database;
  }
}
```

### 4. Main App Setup

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'providers/database_provider.dart';
import 'database/database.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database
  final database = await AppDatabase.instance;
  
  runApp(MyApp(database: database));
}

class MyApp extends StatelessWidget {
  final DeclarativeDatabase database;
  
  const MyApp({Key? key, required this.database}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return DatabaseProvider(
      database: database,
      child: MaterialApp(
        title: 'Declarative SQLite Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
```

## First Flutter Widget

### Simple Query Widget

```dart
// lib/widgets/user_list.dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import '../providers/database_provider.dart';

class UserList extends StatelessWidget {
  const UserList({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final database = DatabaseProvider.of(context);
    
    return QueryListView(
      database: database,
      query: database
        .from('users')
        .where('is_active', equals: true)
        .orderBy('created_at', descending: true),
      itemBuilder: (context, userData) {
        return ListTile(
          title: Text(userData['username'] ?? ''),
          subtitle: Text(userData['email'] ?? ''),
          trailing: Text(
            userData['created_at'] != null
              ? DateTime.parse(userData['created_at']).toString()
              : '',
          ),
        );
      },
      emptyBuilder: (context) => const Center(
        child: Text('No users found'),
      ),
      loadingBuilder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
```

### Stream-based Widget

```dart
// lib/widgets/post_count.dart
import 'package:flutter/material.dart';
import '../providers/database_provider.dart';

class PostCount extends StatelessWidget {
  const PostCount({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final database = DatabaseProvider.of(context);
    
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: database
        .from('posts')
        .where('published', equals: true)
        .stream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        
        final postCount = snapshot.data!.length;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.article, size: 48),
                const SizedBox(height: 8),
                Text(
                  '$postCount',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Text('Published Posts'),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

## Testing Your Setup

Create a simple test to verify everything works:

```dart
// test/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import '../lib/database/schema.dart';

void main() {
  group('Database Tests', () {
    late DeclarativeDatabase database;
    
    setUp(() async {
      database = await DeclarativeDatabase.init(
        path: ':memory:',
        schema: appSchema,
      );
    });
    
    tearDown(() async {
      await database.close();
    });
    
    test('should create and query users', () async {
      // Insert test user
      final userId = await database.insert('users', {
        'username': 'testuser',
        'email': 'test@example.com',
        'full_name': 'Test User',
      });
      
      expect(userId, isNotNull);
      
      // Query user
      final users = await database.query('users');
      expect(users, hasLength(1));
      expect(users.first['username'], equals('testuser'));
    });
    
    test('should stream user updates', () async {
      final stream = database.from('users').stream();
      
      // Listen to stream
      final streamTest = expectLater(
        stream,
        emitsInOrder([
          isEmpty,  // Initial empty state
          hasLength(1),  // After insert
        ]),
      );
      
      // Insert user
      await database.insert('users', {
        'username': 'streamtest',
        'email': 'stream@example.com',
      });
      
      await streamTest;
    });
  });
}
```

## Widget Testing

```dart
// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import '../lib/providers/database_provider.dart';
import '../lib/widgets/user_list.dart';
import '../lib/database/schema.dart';

void main() {
  group('Widget Tests', () {
    late DeclarativeDatabase database;
    
    setUp(() async {
      database = await DeclarativeDatabase.init(
        path: ':memory:',
        schema: appSchema,
      );
    });
    
    tearDown(() async {
      await database.close();
    });
    
    testWidgets('UserList should display users', (tester) async {
      // Insert test data
      await database.insert('users', {
        'username': 'testuser1',
        'email': 'test1@example.com',
        'is_active': true,
      });
      
      await database.insert('users', {
        'username': 'testuser2',
        'email': 'test2@example.com',
        'is_active': true,
      });
      
      // Build widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatabaseProvider(
              database: database,
              child: const UserList(),
            ),
          ),
        ),
      );
      
      // Wait for stream to emit
      await tester.pumpAndSettle();
      
      // Verify users are displayed
      expect(find.text('testuser1'), findsOneWidget);
      expect(find.text('testuser2'), findsOneWidget);
    });
  });
}
```

## Debugging and Development

### Enable Query Logging

```dart
final database = await DeclarativeDatabase.init(
  path: 'app.db',
  schema: appSchema,
  options: DatabaseOptions(
    logQueries: true,  // Log all SQL queries to console
    logMigrations: true,  // Log migration steps
  ),
);
```

### Database Inspector

For debugging, you can create a simple database inspector:

```dart
// lib/debug/database_inspector.dart
import 'package:flutter/material.dart';
import '../providers/database_provider.dart';

class DatabaseInspector extends StatelessWidget {
  const DatabaseInspector({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final database = DatabaseProvider.of(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Database Inspector')),
      body: ListView(
        children: [
          _buildTableInspector('users', database),
          _buildTableInspector('posts', database),
        ],
      ),
    );
  }
  
  Widget _buildTableInspector(String tableName, database) {
    return ExpansionTile(
      title: Text(tableName),
      children: [
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: database.from(tableName).stream(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            
            final data = snapshot.data!;
            
            return Column(
              children: [
                Text('Count: ${data.length}'),
                ...data.map((row) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(row.toString()),
                  ),
                )),
              ],
            );
          },
        ),
      ],
    );
  }
}
```

## Common Issues and Solutions

### Issue: `MissingPluginException`

**Solution**: Make sure you have `sqflite` in your dependencies for mobile platforms.

```yaml
dependencies:
  sqflite: ^2.3.4  # Add this for iOS/Android
```

### Issue: Database path errors

**Solution**: Use `path_provider` to get the correct directory:

```dart
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

final documentsDirectory = await getApplicationDocumentsDirectory();
final path = join(documentsDirectory.path, 'app.db');
```

### Issue: Hot reload doesn't update database

**Solution**: The database connection persists across hot reloads. For testing schema changes, use hot restart instead of hot reload.

### Issue: Streams not updating in widgets

**Solution**: Make sure you're using `StreamBuilder` or `QueryListView` and the stream is properly created:

```dart
// ✅ Correct - creates new stream each time
StreamBuilder(
  stream: database.from('users').stream(),
  builder: (context, snapshot) { ... },
)

// ❌ Incorrect - caches old stream
final stream = database.from('users').stream();
StreamBuilder(
  stream: stream,  // This won't update
  builder: (context, snapshot) { ... },
)
```

## Next Steps

Now that you have Flutter integration set up:

- Learn about [Reactive Widgets](./widgets) for building UIs
- Explore [Form Integration](./forms) for data input
- See [Examples](./examples) for complete app patterns
- Check out [Performance Tips](../advanced/performance) for optimization