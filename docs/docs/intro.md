---
sidebar_position: 1
---

# Introduction

Welcome to the official documentation for **Declarative SQLite**, a comprehensive ecosystem for declarative SQLite schema management, data operations, and real-time synchronization in Dart and Flutter.

## What is Declarative SQLite?

Declarative SQLite provides a fluent, type-safe, and reactive API for interacting with SQLite databases. It is designed to abstract away the complexities of manual schema migrations, raw SQL queries, and change tracking, allowing you to focus on building your application's features.

The ecosystem is built as a monorepo containing several key packages:

- **`declarative_sqlite`**: The core library providing the foundational features.
- **`declarative_sqlite_flutter`**: Flutter-specific widgets and helpers for seamless UI integration.
- **`declarative_sqlite_generator`**: A code generator to reduce boilerplate and improve type safety.
- **`demo`**: A complete Flutter application showcasing best practices and common use cases.

## Core Philosophy

1.  **Declarative Schema Management**: Define your database schema using a fluent Dart API. The library handles schema creation and management automatically.
2.  **Reactive Data Access**: Built around `Stream`s for reactive applications where UI updates automatically when data changes.
3.  **Type Safety**: Query builder and code generation provide compile-time type checking and autocompletion.
4.  **Simple Integration**: Easy integration with Flutter widgets for data-driven UIs.

## Who is this for?

- **Flutter Developers** building data-driven applications that require a local database.
- **Dart Developers** working on server-side or standalone applications needing a simple yet powerful database solution.
- Developers who want to avoid writing raw SQL and manual migration scripts.
- Teams looking for a structured, maintainable, and scalable way to manage their application's database.

## How to Use These Docs

- **Getting Started**: This section will guide you through the initial setup, from installation to creating your first database and schema.
- **Core Library**: A deep dive into the features of the main `declarative_sqlite` package, including advanced queries, synchronization, and file management.
- **Flutter Integration**: Learn how to use the Flutter-specific widgets to quickly build reactive user interfaces.
- **Generator**: Understand how to use code generation to automate boilerplate and improve your development workflow.

Ready to get started? Head over to the [Installation](./getting-started/installation.md) guide.
