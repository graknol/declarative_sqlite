# Schema Definition

Learn how to define your database schema using Declarative SQLite's fluent builder API.

## Overview

Schema definition in Declarative SQLite is declarative and type-safe. You describe what your database should look like, and the library handles creating tables, columns, indexes, and views automatically.

## Basic Schema Structure

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

void buildSchema(SchemaBuilder builder) {
  // Define tables using the table() method
  builder.table('table_name', (table) {
    // Define columns and constraints
  });
  
  // Define views using the view() method
  builder.view('view_name', (view) {
    // Define view query
  });
}
```

## Defining Tables

### Basic Table Definition

```dart
builder.table('users', (table) {
  table.guid('id').notNull();
  table.text('name').notNull();
  table.text('email').notNull();
  table.key(['id']).primary();
});
```

### Table Naming Rules

- Table names must be valid SQL identifiers
- Names starting with `__` (double underscore) are reserved for system tables
- Use snake_case for consistency (e.g., `user_profiles`, `order_items`)

## Column Types

Declarative SQLite supports several column types with built-in validation:

### Text Columns

```dart
table.text('name').notNull();
table.text('description'); // Optional text
table.text('email').notNull(); // Required text
```

### Integer Columns

```dart
table.integer('age').min(0).max(150);
table.integer('count').notNull().min(0);
table.integer('priority').defaultValue(1);
```

### Real Columns (Floating Point)

```dart
table.real('price').min(0.0);
table.real('latitude').min(-90.0).max(90.0);
table.real('percentage').min(0.0).max(100.0);
```

### Date Columns

Date columns store DateTime values as ISO 8601 strings:

```dart
table.date('created_at').notNull();
table.date('updated_at'); // Optional
table.date('birth_date').notNull();
```

### GUID Columns

GUID columns are for UUID/GUID identifiers:

```dart
table.guid('id').notNull();
table.guid('user_id').notNull();
table.guid('session_id'); // Optional
```

### Fileset Columns

For managing file attachments:

```dart
table.fileset('attachments').notNull(); // Required fileset
table.fileset('gallery'); // Optional fileset
```

## Column Constraints

### Not Null Constraint

```dart
table.text('name').notNull(); // Column cannot be null
table.integer('age').notNull().min(0); // Chain constraints
```

### Min/Max Constraints

For numeric columns:

```dart
table.integer('age').min(0).max(150);
table.real('price').min(0.0);
table.real('percentage').min(0.0).max(100.0);
```

### Default Values

```dart
table.text('status').notNull().defaultValue('pending');
table.integer('priority').defaultValue(1);
table.date('created_at').notNull(); // Will use current timestamp if not provided
```

## Primary Keys

Define primary keys using the `key()` method:

### Single Column Primary Key

```dart
builder.table('users', (table) {
  table.guid('id').notNull();
  table.text('name').notNull();
  table.key(['id']).primary(); // Single column primary key
});
```

### Composite Primary Key

```dart
builder.table('user_roles', (table) {
  table.guid('user_id').notNull();
  table.guid('role_id').notNull();
  table.date('assigned_at').notNull();
  table.key(['user_id', 'role_id']).primary(); // Composite primary key
});
```

## Views

Define SQL views for complex queries:

```dart
builder.view('user_post_counts', (view) {
  view.select('users.id')
      .select('users.name')
      .select('COUNT(posts.id)', 'post_count')
      .from('users')
      .leftJoin('posts', col('users.id').eq(col('posts.user_id')))
      .groupBy(['users.id', 'users.name']);
});
```

### View Query Builder

The view builder supports common SQL operations:

```dart
builder.view('active_users', (view) {
  view.select('id')
      .select('name')
      .select('email')
      .from('users')
      .where(col('last_login').gt('date("now", "-30 days")'))
      .orderBy(['last_login DESC']);
});

builder.view('post_summaries', (view) {
  view.select('posts.id')
      .select('posts.title')
      .select('users.name', 'author')
      .select('posts.created_at')
      .from('posts')
      .innerJoin('users', col('posts.user_id').eq(col('users.id')))
      .where(col('posts.published').eq(1))
      .orderBy(['posts.created_at DESC']);
});
```

## Advanced Schema Examples

### Blog Database Schema

```dart
void buildBlogSchema(SchemaBuilder builder) {
  // Users table
  builder.table('users', (table) {
    table.guid('id').notNull();
    table.text('username').notNull();
    table.text('email').notNull();
    table.text('password_hash').notNull();
    table.text('display_name').notNull();
    table.date('created_at').notNull();
    table.date('last_login');
    table.key(['id']).primary();
  });

  // Posts table
  builder.table('posts', (table) {
    table.guid('id').notNull();
    table.guid('author_id').notNull();
    table.text('title').notNull();
    table.text('content').notNull();
    table.text('excerpt');
    table.integer('published').notNull().defaultValue(0); // 0 = draft, 1 = published
    table.date('created_at').notNull();
    table.date('updated_at').notNull();
    table.date('published_at');
    table.key(['id']).primary();
  });

  // Comments table
  builder.table('comments', (table) {
    table.guid('id').notNull();
    table.guid('post_id').notNull();
    table.guid('author_id');
    table.text('author_name').notNull();
    table.text('author_email').notNull();
    table.text('content').notNull();
    table.integer('approved').notNull().defaultValue(0);
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });

  // Tags table
  builder.table('tags', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.text('slug').notNull();
    table.key(['id']).primary();
  });

  // Post-Tag relationships (many-to-many)
  builder.table('post_tags', (table) {
    table.guid('post_id').notNull();
    table.guid('tag_id').notNull();
    table.key(['post_id', 'tag_id']).primary();
  });

  // Useful views
  builder.view('published_posts', (view) {
    view.select('posts.*')
        .select('users.display_name', 'author_name')
        .from('posts')
        .innerJoin('users', col('posts.author_id').eq(col('users.id')))
        .where(col('posts.published').eq(1))
        .orderBy(['posts.published_at DESC']);
  });

  builder.view('post_comment_counts', (view) {
    view.select('posts.id')
        .select('posts.title')
        .select('COUNT(comments.id)', 'comment_count')
        .from('posts')
        .leftJoin('comments', and([
          col('posts.id').eq(col('comments.post_id')),
          col('comments.approved').eq(1)
        ]))
        .groupBy(['posts.id', 'posts.title']);
  });
}
```

### E-commerce Schema

```dart
void buildEcommerceSchema(SchemaBuilder builder) {
  // Products table
  builder.table('products', (table) {
    table.guid('id').notNull();
    table.text('name').notNull();
    table.text('description');
    table.text('sku').notNull();
    table.real('price').min(0.0).notNull();
    table.integer('stock_quantity').min(0).notNull();
    table.integer('active').notNull().defaultValue(1);
    table.fileset('images'); // Product images
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });

  // Customers table
  builder.table('customers', (table) {
    table.guid('id').notNull();
    table.text('email').notNull();
    table.text('first_name').notNull();
    table.text('last_name').notNull();
    table.text('phone');
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });

  // Orders table
  builder.table('orders', (table) {
    table.guid('id').notNull();
    table.guid('customer_id').notNull();
    table.text('status').notNull().defaultValue('pending');
    table.real('total_amount').min(0.0).notNull();
    table.date('created_at').notNull();
    table.date('shipped_at');
    table.key(['id']).primary();
  });

  // Order items table
  builder.table('order_items', (table) {
    table.guid('id').notNull();
    table.guid('order_id').notNull();
    table.guid('product_id').notNull();
    table.integer('quantity').min(1).notNull();
    table.real('unit_price').min(0.0).notNull();
    table.real('total_price').min(0.0).notNull();
    table.key(['id']).primary();
  });

  // Order summary view - corrected to use proper builder pattern
  builder.view('order_summaries', (view) {
    view.select('orders.id')
        .select('orders.created_at')
        .select('customers.first_name || " " || customers.last_name', 'customer_name')
        .select('orders.status')
        .select('orders.total_amount')
        .select('COUNT(order_items.id)', 'item_count')
        .from('orders')
        .innerJoin('customers', col('orders.customer_id').eq(col('customers.id')))
        .leftJoin('order_items', col('orders.id').eq(col('order_items.order_id')))
        .groupBy(['orders.id', 'customers.first_name', 'customers.last_name', 'orders.status', 'orders.total_amount', 'orders.created_at']);
  });
}
```

## Schema Migration

Declarative SQLite automatically handles schema migrations when you modify your schema definition:

### Adding New Columns

```dart
// Before
builder.table('users', (table) {
  table.guid('id').notNull();
  table.text('name').notNull();
  table.key(['id']).primary();
});

// After - new columns are automatically added
builder.table('users', (table) {
  table.guid('id').notNull();
  table.text('name').notNull();
  table.text('email'); // New optional column
  table.date('created_at'); // New optional column
  table.key(['id']).primary();
});
```

### Adding New Tables

Simply add new table definitions to your schema - they will be created automatically on the next database initialization.

### Notes on Schema Changes

- **Adding columns**: Fully supported, new columns are added automatically
- **Adding tables**: Fully supported, new tables are created automatically
- **Modifying column constraints**: Limited support, some changes may require manual intervention
- **Removing columns/tables**: Not automatically supported to prevent data loss

## Best Practices

### Schema Organization

```dart
// Group related table definitions together
void buildSchema(SchemaBuilder builder) {
  // User management tables
  _defineUserTables(builder);
  
  // Content management tables
  _defineContentTables(builder);
  
  // System tables
  _defineSystemTables(builder);
  
  // Views
  _defineViews(builder);
}

void _defineUserTables(SchemaBuilder builder) {
  builder.table('users', (table) {
    // ... user table definition
  });
  
  builder.table('user_profiles', (table) {
    // ... user profile table definition
  });
}
```

### Naming Conventions

- Use **snake_case** for table and column names
- Use descriptive names: `user_profiles` instead of `profiles`
- Use consistent ID column naming: `id` for primary keys, `user_id` for foreign keys
- Use consistent timestamp naming: `created_at`, `updated_at`

### Column Design

- Always define primary keys
- Use appropriate column types for data
- Add constraints for data validation
- Consider using GUIDs for primary keys in distributed systems
- Use `notNull()` for required fields

### Performance Considerations

- Define views for complex queries you'll use frequently
- Consider the query patterns when designing your schema
- Use appropriate data types to minimize storage

## Next Steps

Now that you understand schema definition, learn about:

- [Database Operations](database-operations) - How to query and manipulate data
- [Streaming Queries](streaming-queries) - Real-time data updates