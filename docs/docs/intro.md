# Welcome to Declarative SQLite

A comprehensive Dart and Flutter library ecosystem for declarative SQLite schema management and database operations with real-time synchronization capabilities.

## What is Declarative SQLite?

Declarative SQLite transforms how you work with SQLite databases in Dart and Flutter applications. Instead of writing SQL migration scripts and managing database versions manually, you simply declare your desired schema using a fluent, type-safe API.

## Key Benefits

🚀 **No Migration Scripts** - Define your schema once, automatic migrations handle the rest  
🔄 **Real-time Updates** - Streaming queries automatically update your UI when data changes  
🎯 **Typed Records** - Work with typed record classes instead of raw Map objects  
🛡️ **Smart Exception Handling** - REST API-like exception hierarchy for better error handling  
🔗 **Seamless Sync** - Built-in conflict-free synchronization with remote servers  
📁 **File Management** - Integrated file attachments with automatic lifecycle management  
🧩 **Flutter Ready** - Reactive widgets that integrate perfectly with Flutter's architecture

## Quick Example

Define your schema declaratively:

```dart
void buildSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.text('email').notNull();
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });
}
```

Work with typed records instead of raw maps:

```dart
// Register your record types once
RecordMapFactoryRegistry.register<User>(User.fromMap);

// Query with full type safety
final users = await db.queryTyped<User>((q) => q.from('users'));
final user = users.first;

// Direct property access and modification
print('Hello ${user.name}!'); // Type-safe property access
user.email = 'new@example.com'; // Type-safe property setting
await user.save(); // Save changes back to database
```

Use reactive widgets in Flutter:

```dart
QueryListView<User>(
  database: DatabaseProvider.of(context),
  query: (q) => q.from('users'),
  itemBuilder: (context, user) => UserCard(user: user),
)
```

## Architecture Overview

The ecosystem consists of two complementary packages:

- **`declarative_sqlite`** - Core database operations, schema management, and synchronization
- **`declarative_sqlite_flutter`** - Flutter widgets and utilities for reactive UI development

## Getting Started

Ready to get started? Follow our [Installation Guide](getting-started/installation) to add Declarative SQLite to your project, or jump straight into the [Quick Start Guide](getting-started/quick-start) to see it in action.

## Features at a Glance

### Schema Definition
- Fluent API for table and column definitions
- Built-in validation and constraints
- Automatic migration handling
- Support for views and indexes

### Database Operations
- Type-safe query builder with typed record support
- Streaming queries for real-time updates
- Transaction support
- Smart CRUD vs read-only record intelligence
- REST API-like exception handling
- Efficient bulk operations

### Flutter Integration
- `DatabaseProvider` for dependency injection
- `QueryListView` for reactive lists
- `ServerSyncManagerWidget` for background sync
- Seamless integration with Flutter's widget system

### Synchronization
- Last-Writer-Wins conflict resolution
- Automatic dirty tracking
- Configurable sync intervals
- Robust error handling and retry logic

### File Management
- `FilesetField` for file attachments
- Automatic file lifecycle management
- Support for multiple files per field
- Integration with database transactions