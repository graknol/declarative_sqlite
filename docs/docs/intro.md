---
sidebar_position: 1
---

# Introduction

Welcome to **Declarative SQLite** - a comprehensive Dart and Flutter library ecosystem for declarative SQLite schema management and database operations.

## What is Declarative SQLite?

Declarative SQLite is a modern approach to database development that lets you define your database schema declaratively using a fluent builder pattern. Instead of writing SQL migrations, you describe your desired schema structure and let the library handle the rest.

### Key Benefits

- **🏗️ Declarative Schema Definition** - Define tables, columns, and relationships using type-safe builders
- **🔄 Automatic Migration** - No more manual migration scripts - changes are applied automatically
- **⚡ Real-time Streaming** - Built-in reactive streams for live data updates
- **🔗 LWW Conflict Resolution** - Last-Write-Wins strategy for offline-first applications
- **📱 Flutter Integration** - Seamless integration with Flutter widgets and forms
- **🔧 Code Generation** - Automatically generate type-safe data classes
- **🌊 Reactive UI** - Build reactive user interfaces that update automatically

## Package Ecosystem

This library consists of three main packages:

### 📦 [declarative_sqlite](./core-library/installation)
The core Dart package providing:
- Declarative schema definition
- Database operations and querying
- Streaming query support
- Sync management
- Fileset field support

### 📱 [declarative_sqlite_flutter](./flutter/installation)
Flutter-specific integration providing:
- Reactive ListView widgets
- Form integration components
- Master-detail patterns
- Input field widgets
- Stream-based UI updates

### 🔧 [declarative_sqlite_generator](./generator/setup)
Code generation tools providing:
- Automatic data class generation
- Type-safe database operations
- Build system integration

## Quick Example

Here's a taste of what Declarative SQLite looks like:

```dart
// Define your schema
final schema = SchemaBuilder()
  .table('users', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('username', (col) => col.notNull().unique())
    .text('email', (col) => col.notNull())
    .integer('age')
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now())))
  .table('posts', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('title', (col) => col.notNull())
    .text('content')
    .integer('user_id', (col) => col.notNull())
    .foreignKey('user_id').references('users', 'id'));

// Initialize your database
final database = await DeclarativeDatabase.init(
  path: 'my_app.db',
  schema: schema,
);

// Query with real-time updates
final usersStream = database.users().stream();
usersStream.listen((users) {
  print('Found ${users.length} users');
});
```

## Ready to Get Started?

Choose your path:

- **New to Declarative SQLite?** Start with our [Quick Start Guide](./getting-started/quick-start)
- **Migrating from traditional SQLite?** Check out our [Migration Guide](./advanced/migration-guide)
- **Want to see examples?** Browse our [code examples](./getting-started/examples)
- **Looking for specific features?** Jump to the [API Reference](../api/overview)
