# Declarative SQLite

A comprehensive Dart and Flutter library ecosystem for declarative SQLite schema management and database operations with real-time synchronization capabilities.

## Overview

Declarative SQLite provides a fluent, type-safe API for defining database schemas and managing data with automatic migrations, streaming queries, and built-in synchronization features. The ecosystem consists of two main packages that work together seamlessly.

## Packages

### 📦 Core Library (`declarative_sqlite`)

The foundation package providing declarative schema definition and database operations.

**Key Features:**
- **Declarative Schema Definition**: Define tables, columns, and relationships using a fluent builder API
- **Automatic Migration**: Schema changes are automatically applied to the database
- **Streaming Queries**: Real-time reactive queries that automatically update when data changes
- **File Management**: Built-in support for file attachments with FilesetField
- **Synchronization**: Conflict-free synchronization with remote servers using Last-Writer-Wins (LWW)
- **Type Safety**: Full type safety with proper column type definitions

### 📱 Flutter Integration (`declarative_sqlite_flutter`)

Flutter-specific widgets and utilities that integrate seamlessly with the core library.

**Key Features:**
- **DatabaseProvider**: InheritedWidget for managing database lifecycle
- **QueryListView**: Reactive ListView that automatically updates when database changes
- **ServerSyncManagerWidget**: Widget for managing background synchronization
- **Seamless Integration**: Works with any Flutter app architecture

## Quick Start

### Core Library (Dart)

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

// Define your schema
void buildSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.text('email').notNull();
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });
}

// Initialize database
final database = DeclarativeDatabase(
  schema: buildSchema,
  path: 'my_app.db',
);

// Perform operations
await database.insert('users', {
  'id': 'user-123',
  'name': 'John Doe',
  'email': 'john@example.com',
  'created_at': DateTime.now().toIso8601String(),
});

// Query data
final users = await database.query('users');

// Stream live updates
final userStream = database.streamQuery('users');
userStream.listen((users) {
  print('Users updated: ${users.length} total users');
});
```

### Flutter Integration

```dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: DatabaseProvider(
        schema: buildSchema,
        databaseName: 'app.db',
        child: UserListScreen(),
      ),
    );
  }
}

class UserListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Users')),
      body: QueryListView<User>(
        database: DatabaseProvider.of(context),
        query: (q) => q.from('users').orderBy('name'),
        mapper: User.fromMap,
        itemBuilder: (context, user) => ListTile(
          title: Text(user.name),
          subtitle: Text(user.email),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addUser(context),
        child: Icon(Icons.add),
      ),
    );
  }
  
  Future<void> _addUser(BuildContext context) async {
    final db = DatabaseProvider.of(context);
    await db.insert('users', {
      'id': 'user-${DateTime.now().millisecondsSinceEpoch}',
      'name': 'New User',
      'email': 'user@example.com',
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

class User {
  final String id;
  final String name;
  final String email;
  final DateTime createdAt;

  User({required this.id, required this.name, required this.email, required this.createdAt});

  static User fromMap(Map<String, Object?> map) {
    return User(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
```

## Schema Definition

The schema builder provides a fluent API for defining your database structure:

```dart
void buildSchema(SchemaBuilder builder) {
  // Define a users table
  builder.table('users', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.text('email').notNull();
    table.integer('age').min(0);
    table.date('created_at').notNull();
    table.date('updated_at');
    table.key(['id']).primary();
  });

  // Define a posts table with relationships
  builder.table('posts', (table) {
    table.guid('id').notNull();
    table.guid('user_id').notNull();
    table.text('title').notNull();
    table.text('content');
    table.date('created_at').notNull();
    table.key(['id']).primary();
    // Foreign key relationships are handled at the application level
  });

  // Define a view for post summaries
  builder.view('post_summaries', (view) {
    view.select('posts.id, posts.title, users.name as author')
        .from('posts')
        .join('users', 'posts.user_id = users.id');
  });
}
```

## Column Types

The library supports various column types with built-in validation:

- **`text(name)`**: Text/string columns with optional constraints
- **`integer(name)`**: Integer columns with min/max validation
- **`real(name)`**: Real number (double) columns with min/max validation
- **`date(name)`**: DateTime columns (stored as ISO 8601 strings)
- **`guid(name)`**: GUID/UUID columns for unique identifiers
- **`fileset(name)`**: File attachment columns for managing file collections

All columns support:
- **`.notNull()`**: Make column required
- **`.min(value)`** / **`.max(value)`**: Set validation constraints
- **`.defaultValue(value)`**: Set default values

## File Management

FilesetField provides managed file attachments:

```dart
// Define a table with file attachments
builder.table('documents', (table) {
  table.guid('id').notNull();
  table.text('title').notNull();
  table.fileset('attachments').notNull(); // Required fileset
  table.fileset('gallery'); // Optional fileset
  table.key(['id']).primary();
});

// Work with files in your data models
class Document {
  final String id;
  final String title;
  final FilesetField attachments;
  final FilesetField? gallery;

  static Document fromMap(Map<String, Object?> map, DeclarativeDatabase db) {
    return Document(
      id: map['id'] as String,
      title: map['title'] as String,
      attachments: DataMappingUtils.filesetFieldFromValue(map['attachments'], db)!,
      gallery: DataMappingUtils.filesetFieldFromValue(map['gallery'], db),
    );
  }
}

// Use FilesetField methods
final document = documents.first;
final fileId = await document.attachments.addFile('report.pdf', pdfBytes);
final files = await document.attachments.getFiles();
await document.attachments.deleteFile(fileId);
```

## Synchronization

Built-in synchronization with conflict resolution:

```dart
// Setup sync in Flutter
ServerSyncManagerWidget(
  fetchInterval: Duration(minutes: 2),
  onFetch: (database, table, lastSynced) async {
    // Fetch updates from your server
    final updates = await apiClient.fetchUpdates(table, lastSynced);
    for (final update in updates) {
      await database.insert(table, update);
    }
  },
  onSend: (operations) async {
    // Send local changes to server
    return await apiClient.sendChanges(operations);
  },
  child: MyApp(),
)

// Sync operations are automatically tracked
await database.insert('users', userData); // Will be synced automatically
await database.update('users', updates, where: 'id = ?', whereArgs: [userId]);
await database.delete('users', where: 'id = ?', whereArgs: [userId]);
```

## Installation

Add the packages to your `pubspec.yaml`:

```yaml
dependencies:
  # Core library (required)
  declarative_sqlite:
    path: declarative_sqlite
    
  # Flutter integration (for Flutter apps)
  declarative_sqlite_flutter:
    path: declarative_sqlite_flutter
    
  # SQLite driver (choose one)
  sqflite: ^2.3.0  # For Flutter apps
  # OR
  sqflite_common_ffi: ^2.3.0  # For standalone Dart apps
```

## Examples

Complete examples are available in each package:

- **Core Library**: [Core usage examples](declarative_sqlite/example/)
- **Flutter Integration**: [Flutter app examples](declarative_sqlite_flutter/example/)

## Architecture

```
┌─────────────────────────────────────┐
│        Flutter Application         │
├─────────────────────────────────────┤
│    declarative_sqlite_flutter      │
│  • DatabaseProvider                │
│  • QueryListView                   │
│  • ServerSyncManagerWidget         │
├─────────────────────────────────────┤
│       declarative_sqlite           │
│  • Schema Definition               │
│  • DeclarativeDatabase             │
│  • Streaming Queries               │
│  • Sync Management                 │
│  • File Management                 │
├─────────────────────────────────────┤
│          SQLite Database           │
└─────────────────────────────────────┘
```

## Development

### Prerequisites
- Dart SDK 3.5.3 or later
- Flutter SDK (for Flutter package)

### Building Core Library
```bash
cd declarative_sqlite
dart pub get
dart test
dart analyze
```

### Building Flutter Library
```bash
cd declarative_sqlite_flutter
flutter pub get
flutter test
flutter analyze
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.