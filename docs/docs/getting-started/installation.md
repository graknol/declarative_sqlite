---
sidebar_position: 1
---

# Installation

Setting up `declarative_sqlite` involves adding the required packages to your `pubspec.yaml` and choosing the appropriate SQLite driver for your target platform.

## 1. Add Dependencies

The ecosystem is split into multiple packages. Add the ones you need for your project.

### For Flutter Projects

For a standard Flutter application, you'll need the core library, the Flutter integration package, and the `sqflite` driver. If you plan to use code generation (recommended), you'll also need the generator and `build_runner`.

```yaml title="pubspec.yaml"
dependencies:
  flutter:
    sdk: flutter
  # Core library
  declarative_sqlite: ^1.0.1
  # Flutter-specific widgets and helpers
  declarative_sqlite_flutter: ^1.0.1
  # Standard SQLite plugin for Flutter
  sqflite: ^2.3.3

dev_dependencies:
  # Code generator for DbRecord classes
  declarative_sqlite_generator: ^1.0.1
  # Standard Dart build tool
  build_runner: ^2.4.10
```

### For Standalone Dart Projects

For command-line or server-side Dart applications, you'll need the core library and the `sqflite_common_ffi` driver.

```yaml title="pubspec.yaml"
dependencies:
  # Core library
  declarative_sqlite: ^1.0.1
  # FFI-based SQLite driver for Dart
  sqflite_common_ffi: ^2.3.3

dev_dependencies:
  # Code generator for DbRecord classes
  declarative_sqlite_generator: ^1.0.1
  # Standard Dart build tool
  build_runner: ^2.4.10
```

After adding the dependencies, run `flutter pub get` or `dart pub get` to install them.

## 2. Initialize the Database Driver (Dart Only)

For standalone Dart applications using FFI, you need to initialize the `sqflite_common_ffi` driver at the beginning of your application's entry point.

```dart title="bin/my_app.dart"
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize FFI
  sqfliteFfiInit();

  // Your application logic here...
}
```

Flutter projects using the standard `sqflite` package do **not** need this step, as initialization is handled automatically.

## 3. Configure the Code Generator (Optional, but Recommended)

To enable code generation for your `DbRecord` classes, create a `build.yaml` file in the root of your project. This file tells the generator where to find your schema definition, which is necessary for creating typed accessors.

```yaml title="build.yaml"
targets:
  $default:
    builders:
      declarative_sqlite_generator:
        options:
          # Relative path to the file containing your schema builder function
          schema_definition_file: "lib/database/schema.dart"
```

Replace `"lib/database/schema.dart"` with the actual path to your schema definition file.

## Next Steps

With the installation complete, you're ready to define your first schema.

- **Next**: [Defining a Schema](./defining-a-schema.md)
