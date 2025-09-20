# Welcome to Declarative SQLite

A comprehensive Dart and Flutter library ecosystem for declarative SQLite schema management and database operations with real-time synchronization capabilities.

## What is Declarative SQLite?

Declarative SQLite transforms how you work with SQLite databases in Dart and Flutter applications. Instead of writing SQL migration scripts and managing database versions manually, you simply declare your desired schema using a fluent, type-safe API.

## Key Benefits

🚀 **No Migration Scripts** - Define your schema once, automatic migrations handle the rest  
🔄 **Real-time Updates** - Streaming queries automatically update your UI when data changes  
🔗 **Seamless Sync** - Built-in conflict-free synchronization with remote servers  
📁 **File Management** - Integrated file attachments with automatic lifecycle management  
🎯 **Type Safety** - Full type safety from schema definition to data access  
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

Use reactive widgets in Flutter:

```dart
QueryListView<User>(
  database: DatabaseProvider.of(context),
  query: (q) => q.from('users'),
  mapper: User.fromMap,
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
- Type-safe query builder
- Streaming queries for real-time updates
- Transaction support
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