---
sidebar_position: 1
---

# Introduction

The core `declarative_sqlite` library is the powerhouse of the ecosystem. It contains all the essential tools for defining your schema, managing migrations, querying data, and handling data synchronization.

This section provides a deep dive into the advanced features of the core library.

## Key Feature Areas

### Querying
- **Query Builder**: A fluent, type-safe API for constructing complex SQL queries. It supports `SELECT`, `JOIN`, `WHERE`, `GROUP BY`, `ORDER BY`, and more, reducing the risk of syntax errors.
- **Streaming Queries**: The foundation for building reactive applications. These queries return a `Stream` that automatically emits a new list of results whenever the underlying data changes. The library performs sophisticated dependency analysis to ensure that streams are only updated when relevant data is modified.

### Data Modeling
- **`DbRecord` and Code Generation**: A pattern for creating typed data models that map directly to your database tables. The `declarative_sqlite_generator` package can be used to automatically generate typed getters and setters, eliminating boilerplate and improving code safety.
- **File Management**: A robust system for associating files with your database records. The `fileset` column type allows you to manage collections of files, with built-in support for adding, retrieving, deleting, and garbage-collecting file assets.

### Synchronization
- **Hybrid Logical Clock (HLC)**: At the heart of the synchronization system is the HLC, a timestamping mechanism that combines physical time with a logical counter. This ensures a consistent, conflict-free ordering of operations across distributed clients (e.g., multiple devices syncing with a central server).
- **Change Tracking**: When enabled, the library automatically tracks all `INSERT`, `UPDATE`, and `DELETE` operations in a "dirty rows" table. This log of changes is used by the synchronization manager to send pending operations to a remote server.
- **Sync Manager**: A `ServerSyncManager` class orchestrates the two-way synchronization process: fetching changes from a server and sending local changes up to it.

### Task Scheduling
- **Background Task Scheduler**: A sophisticated, priority-based task scheduler is included for managing background operations like data synchronization and database maintenance (e.g., file garbage collection). It supports concurrency limits, backoff-and-retry strategies, and network connectivity awareness to ensure that background tasks run efficiently without impacting application performance or battery life.

## What You'll Learn

In this section, you will learn how to:
- Build complex, multi-table queries with the **Query Builder**.
- Create reactive user interfaces with **Streaming Queries**.
- Model your data effectively using **`DbRecord`** and **Code Generation**.
- Attach and manage files with the **File Management** system.
- Implement offline-first data **Synchronization**.
- Schedule and manage **Background Tasks**.
