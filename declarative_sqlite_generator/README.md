# Declarative SQLite Generator

A build-time code generator that creates boilerplate code for `declarative_sqlite`, enhancing productivity and reducing errors.

This generator inspects your `DbRecord` classes and your database schema to generate helpful extensions, including typed getters/setters.

## Features

- **Typed Record Classes**: Automatically generates a `.db.dart` file for each of your `DbRecord` subclasses. This file contains an extension with typed getters and setters for every column in the corresponding table. This gives you full type safety and autocompletion when accessing record data.
- **Factory Registration**: Creates a `sqlite_factory_registration.dart` file that contains a `SqliteFactoryRegistration.registerAllFactories()` function. Calling this function once at startup automatically registers all your record classes with the `RecordMapFactoryRegistry`, allowing `declarative_sqlite` to automatically map query results to your typed objects.

## Getting Started

Add the necessary packages to your `pubspec.yaml`:

```yaml
dependencies:
  declarative_sqlite: ^1.0.1

dev_dependencies:
  build_runner: ^2.4.10
  declarative_sqlite_generator: ^1.0.1
```

## Usage

1.  **Annotate your `DbRecord` classes:**
    Add the `@GenerateDbRecord('table_name')` annotation to your `DbRecord` subclasses.

    ```dart
    // lib/user.dart
    import 'package:declarative_sqlite/declarative_sqlite.dart';

    part 'user.db.dart'; // Important: Add part file directive

    @GenerateDbRecord('users')
    class User extends DbRecord {
      User(super.data, super.database) : super(tableName: 'users');

      // Typed accessors will be available via the generated extension
      String get name => _user.name;
      set name(String value) => _user.name = value;
    }
    ```

2.  **Create a `build.yaml` file:**
    In your project's root directory, create a `build.yaml` file to configure the generator. This tells `build_runner` where to find your schema definition.

    ```yaml
    targets:
      $default:
        builders:
          declarative_sqlite_generator:
            options:
              # Path to the file containing your schema definition function
              schema_definition_file: "lib/schema.dart"
    ```

3.  **Run the generator:**
    Execute the `build_runner` command to generate the necessary files.

    ```bash
    dart run build_runner build --delete-conflicting-outputs
    ```

    This will create:
    *   `lib/user.db.dart` (the generated part file with the extension)
    *   `lib/sqlite_factory_registration.dart` (the factory registration helper)

4.  **Initialize Factory Registration:**
    In your app's main entry point, call the generated `initFactoryRegistration()` function before you initialize your database.

    ```dart
    import 'package:declarative_sqlite/declarative_sqlite.dart';
    import 'sqlite_factory_registration.dart'; // Import generated file

    void main() {
      // Register all your generated factories
      SqliteFactoryRegistration.registerAllFactories();

      // Now you can initialize your database
      final database = DeclarativeDatabase(...);
      // ...
    }
    ```

Now, when you query the database, it can automatically return instances of your typed `User` class without needing to pass a `mapper` function.
