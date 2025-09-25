# Declarative SQLite

A comprehensive Dart and Flutter library ecosystem for declarative SQLite schema management and database operations with real-time synchronization capabilities.

## Overview

Declarative SQLite provides a fluent, type-safe API for defining database schemas and managing data with automatic migrations, streaming queries, and built-in synchronization features. The ecosystem consists of multiple packages that work together seamlessly to provide a robust database solution for Dart and Flutter applications.

## Packages

### 📦 Core Library (`declarative_sqlite`)

The foundation of the ecosystem. It provides all the core functionality for schema definition, data manipulation, and synchronization.

**Key Features:**
- **Declarative Schema**: Define your database schema using a fluent, easy-to-read builder API.
- **Automatic Migrations**: The library automatically detects schema changes and generates/applies the necessary migration scripts.
- **Type-Safe Queries**: Build complex SQL queries with type safety and autocompletion.
- **Streaming Queries**: Create reactive queries that automatically emit new results when underlying data changes.
- **Conflict-Free Sync**: Built-in support for data synchronization using a Hybrid Logical Clock (HLC) to ensure conflict-free, last-write-wins data merging.
- **File Management**: Integrated support for attaching and managing files linked to database records.

### 📱 Flutter Integration (`declarative_sqlite_flutter`)

Provides Flutter-specific widgets and utilities to easily integrate `declarative_sqlite` into your Flutter applications.

**Key Features:**
- **`DatabaseProvider`**: An `InheritedWidget` that provides easy access to your database instance throughout the widget tree.
- **`QueryListView`**: A reactive `ListView` that listens to a streaming query and automatically rebuilds itself when the data changes.
- **`ServerSyncManagerWidget`**: A widget to manage the lifecycle of the background data synchronization service.

### ⚙️ Code Generator (`declarative_sqlite_generator`)

A build-time code generator that creates boilerplate code for you, enhancing productivity and reducing errors.

**Key Features:**
- **Typed Record Classes**: Automatically generates typed getters, setters, and `fromMap` constructors for your `DbRecord` classes based on your schema.
- **Factory Registration**: Generates code to automatically register your typed record factories, simplifying database setup.

### 🚀 Demo Application (`demo`)

A complete Flutter application showcasing the features of the `declarative_sqlite` ecosystem in action. Use it as a reference and a starting point for your own projects.

## Getting Started

To get started, add the necessary packages to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  declarative_sqlite: ^1.0.1
  declarative_sqlite_flutter: ^1.0.1

dev_dependencies:
  build_runner: ^2.4.10
  declarative_sqlite_generator: ^1.0.1
```

For a detailed guide, please refer to our [**official documentation**](https://graknol.github.io/declarative_sqlite/).

## Architecture

```
┌─────────────────────────────────────┐
│        Flutter Application         │
├─────────────────────────────────────┤
│    declarative_sqlite_flutter      │
│  • DatabaseProvider                │
│  • QueryListView                   │
│  • ServerSyncManagerWidget         │
├─────────────────────────────────────┤
│       declarative_sqlite           │
│  • Schema Definition & Migration   │
│  • CRUD & Query Builders           │
│  • Streaming Queries               │
│  • HLC-based Sync Management       │
│  • File Management                 │
├─────────────────────────────────────┤
│   declarative_sqlite_generator     │
│  • DbRecord Code Generation        │
├─────────────────────────────────────┤
│          SQLite Database           │
└─────────────────────────────────────┘
```

## Contributing

Contributions are welcome! If you'd like to contribute, please follow these steps:

1.  Fork the repository.
2.  Create a new feature branch (`git checkout -b feature/your-feature`).
3.  Make your changes and add tests.
4.  Ensure all tests pass (`dart test` or `flutter test`).
5.  Submit a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.