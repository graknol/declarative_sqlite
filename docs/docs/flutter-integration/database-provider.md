---
sidebar_position: 2
---

# DatabaseProvider

`DatabaseProvider` is an `InheritedWidget` that simplifies the management and accessibility of your `DeclarativeDatabase` instance within a Flutter application.

It serves two primary purposes:
1.  **Lifecycle Management**: It automatically handles the initialization (`database.init()`) and disposal (`database.close()`) of the database, tying its lifecycle to that of a widget.
2.  **Dependency Injection**: It makes the database instance available to any descendant widget in the widget tree via `DatabaseProvider.of(context)`, avoiding the need to pass the database instance down through multiple layers of widgets.

## Usage

You should wrap a high-level widget in your application—typically your `MaterialApp` or `CupertinoApp`—with `DatabaseProvider`.

```dart title="lib/main.dart"
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'database/schema.dart'; // Your schema definition

void main() {
  runApp(
    DatabaseProvider(
      // The name of the database file (e.g., 'app.db')
      databaseName: 'my_application.db',
      // A reference to your schema builder function
      schema: appSchema,
      // Enable logging for migrations and statements (optional)
      logStatements: true,
      // The rest of your application
      child: const MyApp(),
    ),
  );
}
```

### Parameters

-   `databaseName` (required): The filename for your SQLite database.
-   `schema` (required): A reference to the function that defines your database schema.
-   `child` (required): The widget tree that will have access to the database.
-   `logStatements` (optional): A boolean to enable detailed logging of SQL statements and migration steps. Defaults to `false`.
-   `fileRepository` (optional): An instance of `IFileRepository` if you are using the file management features.

## Accessing the Database

Once `DatabaseProvider` is set up, any widget within its `child` tree can access the database instance by calling the static method `DatabaseProvider.of(context)`.

```dart title="lib/screens/home_screen.dart"
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _addNewTask(BuildContext context) async {
    // 1. Get the database instance from the context.
    final database = DatabaseProvider.of(context);

    // 2. Use the database instance to perform operations.
    await database.insert('tasks', {
      'id': Uuid().v4(),
      'title': 'A new task from HomeScreen',
      'is_completed': 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addNewTask(context),
        child: const Icon(Icons.add),
      ),
      // ...
    );
  }
}
```

This pattern keeps your widgets clean and decoupled from the global state, as they only need a `BuildContext` to get access to the database.

## Behind the Scenes

When the `DatabaseProvider` widget is first inserted into the tree, its `initState` method is called. Inside `initState`, it creates a `DeclarativeDatabase` instance and calls `await database.init()`. This asynchronous initialization means the database is not available immediately.

`DatabaseProvider` shows a `CircularProgressIndicator` while the database is initializing. You can customize this by providing a `loadingBuilder`. Once `init()` completes, the provider rebuilds and makes the database instance available to its children, which then build for the first time with a valid database connection.

When the `DatabaseProvider` is removed from the tree (e.g., when the app is closed), its `dispose` method is called, which in turn calls `database.close()` to safely shut down the database connection.
