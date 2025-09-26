# DeclarativeSQLite Generator

Code generation for DeclarativeSQLite that creates typed record classes and reduces boilerplate.

## Features

- **`@GenerateDbRecord` annotation**: Generates typed accessors for database record classes
- **Build-time code generation**: Uses `build_runner` for compile-time code generation
- **Type safety**: Provides compile-time checking for database field access
- **Integration with core library**: Works seamlessly with `DeclarativeDatabase`

## Installation

Add the packages to your `pubspec.yaml`:

```yaml
dependencies:
  declarative_sqlite: ^1.0.0

dev_dependencies:
  build_runner: ^2.4.0
  declarative_sqlite_generator: ^1.0.0
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
      User(Map<String, Object?> data, DeclarativeDatabase database)
          : super(data, 'users', database);

      // Typed accessors will be generated automatically
      // Generated extension will provide:
      // String get name => getValue('name')!;
      // set name(String value) => setValue('name', value);
      // int get age => getValue('age')!;
      // set age(int value) => setValue('age', value);
    }
    
    // Schema definition (separate file recommended)
    // lib/database/schema.dart
    @DbSchema()
    void buildUserSchema(SchemaBuilder builder) {
      builder.table('users', (table) {
        table.guid('id');
        table.text('name');
        table.integer('age');
        table.text('email');
        table.key(['id']).primary();
      });
    }
    ```

2.  **Run the generator:**
    Execute the `build_runner` command to generate the necessary files.

    ```bash
    dart run build_runner build --delete-conflicting-outputs
    ```

    This will create:
    *   `lib/user.db.dart` (the generated part file with the extension)
    *   `lib/sqlite_factory_registration.dart` (the factory registration helper)

4.  **Use the Generated Code:**
    The generated extensions provide typed access to your record properties.

    ```dart
    import 'package:declarative_sqlite/declarative_sqlite.dart';
    import 'user.dart';

    void main() async {
      // Initialize your database
      final schemaBuilder = SchemaBuilder();
      // ... define your schema
      final schema = schemaBuilder.build();
      
      final database = await DeclarativeDatabase.open(
        'app.db',
        schema: schema,
        databaseFactory: databaseFactory,
        fileRepository: FilesystemFileRepository('files'),
      );

      // Create and use your typed records
      final user = User({}, 'users', database);
      user.name = 'Alice';
      user.setValue('age', 30);
      
      await database.insert('users', user.data);
    }
    ```

The generated extensions provide type-safe access to your record properties, reducing runtime errors and improving development experience with better IDE support.
