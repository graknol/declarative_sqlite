# Declarative SQLite Flutter

A Flutter package that provides seamless integration of declarative_sqlite with Flutter widgets, forms, and UI patterns.

## Features

- **QueryListView**: A reactive ListView that automatically updates when database data changes
- **DatabaseProvider**: InheritedWidget that provides database access throughout the widget tree
- **ServerSyncManagerWidget**: Widget wrapper for automatic server synchronization
- **Full Flutter SDK compatibility**: All widgets expose the same properties as their core Flutter counterparts

## Getting Started

### 1. Set up your database with DatabaseProvider

```dart
DatabaseProvider(
  schema: (builder) {
    builder.table('users', (table) {
      table.guid('id').notNull();
      table.text('name').notNull();
      table.text('email').notNull();
      table.key(['id']).primary();
    });
  },
  databaseName: 'my_app.db',
  child: MyApp(),
)
```

### 2. Use QueryListView for reactive lists

```dart
QueryListView<User>(
  database: DatabaseProvider.of(context),
  query: (q) => q.from('users').orderBy('name'),
  mapper: User.fromMap,
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
  itemBuilder: (context, user) => ListTile(
    title: Text(user.name),
    subtitle: Text(user.email),
  ),
  // All ListView properties are supported
  padding: EdgeInsets.all(8.0),
  physics: BouncingScrollPhysics(),
  shrinkWrap: true,
)
```

### 3. Add server synchronization (optional)

```dart
ServerSyncManagerWidget(
  fetchInterval: Duration(minutes: 5),
  onFetch: (database, table, lastSynced) async {
    // Fetch data from your server
  },
  onSend: (operations) async {
    // Send changes to your server
    return true; // Return true on success
  },
  child: MyApp(),
)
```

## Core Widgets

### QueryListView<T>

A reactive ListView that automatically updates when the underlying database data changes.

**Key Features:**
- Streaming query results with automatic updates
- Smart lifecycle management - detects query and mapper changes
- Full ListView property support for Flutter SDK compatibility
- Efficient updates - only re-renders when data actually changes

**Properties:**
- `database`: DeclarativeDatabase instance (optional, can use DatabaseProvider)
- `query`: Function that builds the SQL query using QueryBuilder
- `mapper`: Function that converts database rows to your data model
- `loadingBuilder`: Widget to show while loading
- `errorBuilder`: Widget to show on error
- `itemBuilder`: Widget builder for each list item
- Plus all standard ListView properties (scrollDirection, padding, physics, etc.)

### DatabaseProvider

An InheritedWidget that provides database access throughout the widget tree.

**Key Features:**
- Automatic database initialization and lifecycle management
- Provides database instance via `DatabaseProvider.of(context)`
- Proper error handling during database initialization
- Schema-based database setup

### ServerSyncManagerWidget

A widget wrapper for automatic server synchronization.

**Key Features:**
- Automatic sync operations based on widget lifecycle
- Configurable sync intervals and retry strategies
- Separation of fetch and send operations
- Proper cleanup when widget is disposed

## Design Principles

This library follows the design principles outlined in the declarative_sqlite ecosystem:

1. **Smaller, composable widgets** over big, complex widgets
2. **Stateless widgets preferred** unless state is absolutely necessary
3. **Composition over inheritance**
4. **Uni-directional data flow** - properties flow down the widget tree
5. **Flutter SDK compatibility** - widgets expose the same properties as core Flutter widgets
6. **No backwards compatibility burden** - clean, modern API design

## Examples

See the `example/` directory for complete working examples:

- `example/main.dart` - Basic QueryListView usage
- `example/sync_demo.dart` - Full sync integration example

## Integration with Core Library

This Flutter library is built on top of the core `declarative_sqlite` library and leverages its:

- **Streaming query system** for reactive UI updates
- **Advanced query builders** for type-safe SQL generation
- **Schema management** for database structure definition
- **Sync infrastructure** for server synchronization
- **File management** for fileset handling

All data flow and synchronization is handled by the core library, while this Flutter library focuses purely on providing excellent widget-based developer experience.