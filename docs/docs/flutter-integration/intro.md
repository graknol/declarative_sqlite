---
sidebar_position: 1
---

# Introduction

The `declarative_sqlite_flutter` package provides a set of widgets and helpers specifically designed to bridge the gap between the core database library and a Flutter application. These tools simplify state management, database lifecycle, and UI updates, allowing you to build reactive, data-driven interfaces with minimal boilerplate.

## Key Components

### `DatabaseProvider`
A Flutter `InheritedWidget` that handles the initialization and lifecycle of your `DeclarativeDatabase` instance. It ensures that your database is opened when the widget is created, closed when it's disposed, and made available to all descendant widgets in the tree. This is the recommended way to manage your database instance in a Flutter app.

### `QueryListView`
A powerful, reactive `ListView` that is directly connected to a `streamQuery`. It automatically listens for data changes and rebuilds its list of items with smooth animations (`AnimatedList`) when the query results are updated. It handles all the complexities of stream subscriptions, state management, and efficient UI updates for lists of data.

## What You'll Learn

In this section, you will learn how to:
-   Properly manage your database lifecycle using **`DatabaseProvider`**.
-   Build dynamic, real-time lists of data with **`QueryListView`**.
