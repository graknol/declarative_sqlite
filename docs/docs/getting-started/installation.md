---
sidebar_position: 1
---

# Installation

Setting up `declarative_sqlite` for Flutter involves adding the required packages to your `pubspec.yaml`. The library uses the standard `sqflite` plugin for Android and iOS compatibility.

## Add Dependencies

For a Flutter application, you'll need the core library, the Flutter integration package, and the `sqflite` driver. If you plan to use code generation (recommended), you'll also need the generator and `build_runner`.

```yaml title="pubspec.yaml"
dependencies:
  flutter:
    sdk: flutter
  # Core library
  declarative_sqlite: ^1.0.1
  # Flutter-specific widgets and helpers
  declarative_sqlite_flutter: ^1.0.1
  # Standard SQLite plugin for Flutter (Android/iOS)
  sqflite: ^2.3.3

dev_dependencies:
  # Code generator for DbRecord classes
  declarative_sqlite_generator: ^1.0.1
  # Standard Dart build tool
  build_runner: ^2.4.10
```

After adding the dependencies, run `flutter pub get` to install them.

## Database Initialization

Flutter projects using the `sqflite` package do **not** need any special initialization steps. The SQLite driver is automatically available on Android and iOS platforms.

## Next Steps

With the installation complete, you're ready to define your first schema.

- **Next**: [Defining a Schema](./defining-a-schema.md)
