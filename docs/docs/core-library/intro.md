---
sidebar_position: 1
---

# Introduction

The core `declarative_sqlite` library is the powerhouse of the ecosystem. It contains all the essential tools for defining your schema, managing migrations, querying data, and handling Last-Writer-Wins conflict resolution.

This section provides a deep dive into the advanced features of the core library.

## Key Feature Areas

### Querying
- **Query Builder**: A fluent, type-safe API for constructing complex SQL queries. It supports `SELECT`, `JOIN`, `WHERE`, `GROUP BY`, `ORDER BY`, and more, reducing the risk of syntax errors.
- **Streaming Queries**: The foundation for building reactive applications. These queries return a `StreamingQuery` that automatically emits a new list of results whenever the underlying data changes. The library performs sophisticated dependency analysis to ensure that streams are only updated when relevant data is modified.

### Data Modeling
- **`DbRecord` and Code Generation**: A pattern for creating typed data models that map directly to your database tables. The `declarative_sqlite_generator` package can be used to automatically generate typed getters for all columns and setters for LWW columns, eliminating boilerplate and improving code safety.
- **File Management**: A robust system for associating files with your database records. The `fileset` column type allows you to manage collections of files, with built-in support for adding, retrieving, deleting, and garbage-collecting file assets.

### LWW Conflict Resolution
- **Hybrid Logical Clock (HLC)**: Used for Last-Writer-Wins (LWW) columns, the HLC is a timestamping mechanism that combines physical time with a logical counter. This ensures consistent conflict resolution when the same data is modified from multiple sources.
- **LWW Columns**: Special column type that automatically tracks the last modification time using HLC timestamps, enabling conflict-free data merging in distributed scenarios.

## What You'll Learn

In this section, you will learn how to:
- Build complex, multi-table queries with the **Query Builder**.
- Create reactive user interfaces with **Streaming Queries**.
- Model your data effectively using **`DbRecord`** and **Code Generation**.
- Attach and manage files with the **File Management** system.
- Use **LWW Columns** for conflict resolution.
