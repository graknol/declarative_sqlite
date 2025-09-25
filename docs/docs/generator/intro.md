---
sidebar_position: 1
---

# Code Generation

The `declarative_sqlite_generator` package is a powerful tool that uses `build_runner` to automate the creation of boilerplate code. By using code generation, you can significantly improve type safety, reduce manual coding, and make your data models more robust and easier to maintain.

## Why Use Code Generation?

When working with `DbRecord`, you could write typed getters and setters manually for each column. However, this has several drawbacks:
-   It's tedious and repetitive.
-   It's error-prone. A typo in a column name string (`get('titel')`) won't be caught by the compiler.
-   It requires manual updates. If you rename a column in your schema, you have to remember to update the getter/setter in your model class.

Code generation solves these problems by reading your schema directly and creating the necessary code for you.

## What It Generates

For each class annotated with `@GenerateDbRecord`, the generator produces a `.db.dart` part file containing a private extension. This extension includes:
1.  **Typed Getters**: A getter for each column in the associated table, with the correct Dart type.
2.  **Typed Setters**: A setter for each column, with type validation.
3.  **`fromMap` Factory**: A static `fromMap` method that correctly instantiates your `DbRecord` subclass and handles type conversions (e.g., parsing dates, creating `FilesetField` instances).

Additionally, it generates a single `sqlite_factory_registration.dart` file for your entire project, which allows the database to automatically map query results to your typed objects.

## Setup and Configuration

### 1. Add Dependencies

Ensure you have `declarative_sqlite_generator` and `build_runner` in your `dev_dependencies`.

```yaml title="pubspec.yaml"
dependencies:
  declarative_sqlite: ^1.0.1

dev_dependencies:
  build_runner: ^2.4.10
  declarative_sqlite_generator: ^1.0.1
```

### 2. Create `build.yaml`

Create a `build.yaml` file in your project's root directory. This configuration file is essential as it tells the generator where to find your schema definition.

```yaml title="build.yaml"
targets:
  $default:
    builders:
      declarative_sqlite_generator:
        options:
          # Provide the relative path to the file containing your schema function.
          schema_definition_file: "lib/database/schema.dart"
```

### 3. Annotate Your Models

In your model file, add the `@GenerateDbRecord('table_name')` annotation above your class definition and include the `part` directive.

```dart title="lib/models/task.dart"
import 'package:declarative_sqlite/declarative_sqlite.dart';

// This line links the generated file to this one.
part 'task.db.dart';

@GenerateDbRecord('tasks')
class Task extends DbRecord {
  // The constructor must pass the table name to super.
  Task(super.data, super.database) : super(tableName: 'tasks');

  // It's good practice to add a factory that redirects to the generated one.
  factory Task.fromMap(Map<String, Object?> data, DeclarativeDatabase db) {
    return _Task.fromMap(data, db);
  }
}
```

## Running the Generator

To run the code generator, use the `build_runner` command in your terminal:

```bash
# Run a one-time build
dart run build_runner build --delete-conflicting-outputs

# Or, run in watch mode to automatically rebuild on changes
dart run build_runner watch --delete-conflicting-outputs
```

This will create the `task.db.dart` and `sqlite_factory_registration.dart` files.

## Using the Generated Code

### Initialize Factory Registration

In your application's entry point (`main.dart`), import and call the generated `initFactoryRegistration` function. This must be done before you initialize your database.

```dart title="lib/main.dart"
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
// Import the generated registration file
import 'sqlite_factory_registration.dart';
import 'database/schema.dart';

void main() {
  // Register all generated DbRecord factories
  initFactoryRegistration();

  runApp(
    DatabaseProvider(
      databaseName: 'app.db',
      schema: appSchema,
      child: const MyApp(),
    ),
  );
}
```

### Accessing Typed Properties

Now you can interact with your `Task` object in a fully type-safe manner. The generated getters and setters are available directly on the instance.

```dart
// No mapper function is needed because the factory is registered.
final Stream<List<Task>> taskStream = database.streamQuery('tasks');

taskStream.listen((tasks) {
  final firstTask = tasks.first;

  // Use the generated type-safe getter
  String title = firstTask.title;
  print('Task title: $title');

  // Use the generated type-safe setter
  firstTask.isCompleted = true;

  // Save the changes
  firstTask.save();
});
```

By leveraging code generation, you create a more robust, maintainable, and developer-friendly data layer for your application.
