# GitHub Copilot Instructions for the `declarative_sqlite` Project

This document provides guidance for GitHub Copilot to offer the most relevant and helpful suggestions for the `declarative_sqlite` library and its related packages.

## Project Overview

`declarative_sqlite` is a Dart library designed to provide a fluent, declarative, and type-safe way to define and interact with a SQLite database. The core philosophy is to define the entire database schema in code and let the library handle the complexities of database creation, migration, and data access.

The project is divided into three main libraries:

1.  `declarative_sqlite`: The core library for schema definition, migration, and data access logic.
2.  `declarative_sqlite_flutter`: Contains Flutter-specific widgets and helpers for integrating the core library with a Flutter UI (e.g., `QueryListView`).
3.  `ifs_cloud_auth`: A library for handling authentication against an IFS Cloud instance.

## Core Concepts

### 1. Declarative Schema Definition

The database schema is the single source of truth and is defined using a `SchemaBuilder`. This builder has a fluent API for defining tables, columns, keys, and views.

**Example:**

```dart
final schemaBuilder = SchemaBuilder();
schemaBuilder.table('users', (table) {
  table.guid('id').notNull('some_default_id');
  table.text('name').notNull('Default Name');
  table.integer('age').notNull(0);
  table.key(['id']).primary();
  table.key(['name']).index();
});
schemaBuilder.view('user_names', (view) {
  view.select('name').from('users');
});
final schema = schemaBuilder.build();
```

When assisting with schema definition, Copilot should:

- Encourage the use of the fluent builder methods (`.notNull()`, `.primary()`, etc.).
- Remember that `.notNull()` **requires** a default value.
- Guide the user to define parent tables before child tables if there are logical dependencies.

### 2. Automatic Database Migrations

A key feature is the automatic migration system. The library can compare the declarative schema with the live database schema and generate the necessary SQL scripts to update it.

**Key points for Copilot:**

- The migration process is handled by `introspectSchema`, `diffSchemas`, and `generateMigrationScripts`.
- For complex changes (dropping a column, adding a `NOT NULL` constraint, changing a key), the library automatically and safely recreates the table.
- The process involves renaming the old table, creating a new one, copying the data (using `IFNULL` to handle new `NOT NULL` constraints), and then dropping the old table. This is all done in a single transaction.
- When a user wants to add a `NOT NULL` constraint, remind them that they must provide a default value and that the library will handle the data migration automatically.

### 3. API and Coding Style

The project follows a set of strict coding principles. Copilot should always adhere to these when generating code:

- **Composition over Inheritance**: Prefer composing smaller, single-purpose classes and widgets.
- **Stateless over Stateful**: Avoid stateful widgets unless absolutely necessary.
- **Uni-directional Data Flow**: Properties should flow down the widget tree. Avoid passing callbacks up the tree if a more reactive pattern can be used.
- **Imitate Flutter's Core API**: When creating new widgets, their APIs should feel familiar to a Flutter developer. For example, a `QueryListView` should accept properties like `scrollDirection` and pass them to the underlying `ListView`.
- **No Proxies or Helpers**: Implement features directly in the target classes. Avoid creating intermediate classes that just delegate calls.
- **Simplicity and Iteration**: It's better to have a simple, clean implementation that can be iterated upon than a complex one. Encourage refactoring long methods and deeply nested code into smaller, more manageable pieces.
- **No Backwards Compatibility (Yet)**: As the library is still in development, there is no need to maintain backwards compatibility. Feel free to suggest breaking changes if they lead to a cleaner API.

By following these instructions, GitHub Copilot can act as an expert on this specific codebase, providing suggestions that are not just syntactically correct but also align with the project's architecture and design philosophy.

ALWAYS think about the problem first. THEN read your own instructions and follow them! PREFER actions (edit files, reading files, calling tools, etc).
