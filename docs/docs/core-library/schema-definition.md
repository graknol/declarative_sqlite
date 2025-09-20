---
sidebar_position: 2
---

# Schema Definition

Learn how to define your database schema using Declarative SQLite's fluent builder pattern.

## Overview

Schema definition is the foundation of Declarative SQLite. Instead of writing SQL DDL statements, you use a type-safe builder pattern to describe your database structure. The library then automatically creates or migrates your database to match this schema.

## Basic Schema Creation

### Creating a Schema Builder

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final schema = SchemaBuilder()
  .table('users', (table) => {
    // Table definition goes here
  })
  .table('posts', (table) => {
    // Another table definition
  });
```

### Table Definition

```dart
final schema = SchemaBuilder()
  .table('users', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('username', (col) => col.notNull().unique())
    .text('email', (col) => col.notNull())
    .text('full_name')
    .integer('age', (col) => col.min(0).max(150))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('last_login'));
```

## Column Types

Declarative SQLite supports all common SQLite column types with type-safe builders:

### Text Columns

```dart
table
  .text('username')                    // Basic text column
  .text('email', (col) => col
    .notNull()                         // NOT NULL constraint
    .unique()                          // UNIQUE constraint
    .maxLength(255))                   // Maximum length validation
  .text('bio', (col) => col
    .maxLength(1000)
    .defaultValue(''))                 // Default value
```

### Integer Columns

```dart
table
  .integer('age')                      // Basic integer column
  .integer('score', (col) => col
    .notNull()
    .min(0)                           // Minimum value constraint
    .max(100)                         // Maximum value constraint
    .defaultValue(0))
  .autoIncrementPrimaryKey('id')      // Auto-increment primary key
```

### Real (Decimal) Columns

```dart
table
  .real('price', (col) => col
    .notNull()
    .min(0.0)                         // Minimum value
    .precision(2))                    // Decimal precision
  .real('latitude')
  .real('longitude')
```

### Boolean Columns

```dart
table
  .boolean('is_active', (col) => col
    .notNull()
    .defaultValue(true))              // Default to true
  .boolean('is_verified')
```

### Date/DateTime Columns

```dart
table
  .date('created_at', (col) => col
    .notNull()
    .defaultValue(DateTime.now()))    // Default to current time
  .date('updated_at')
  .date('deleted_at')                 // For soft deletes
```

### GUID/UUID Columns

```dart
table
  .guid('id', (col) => col
    .notNull()
    .primary())                       // GUID primary key
  .guid('external_id', (col) => col
    .unique())                        // Unique GUID
```

### Blob (Binary) Columns

```dart
table
  .blob('profile_picture')
  .blob('document_data', (col) => col
    .maxSize(10 * 1024 * 1024))      // 10MB max size
```

### Fileset Columns

For file attachments and collections:

```dart
table
  .fileset('attachments', (col) => col
    .notNull()                        // Required fileset
    .maxFiles(16)                     // Maximum 16 files
    .maxFileSize(8 * 1024 * 1024))   // 8MB per file
  .fileset('gallery')                 // Optional fileset
```

## Column Constraints

### Primary Keys

```dart
// Single column primary key
table.autoIncrementPrimaryKey('id')

// Composite primary key
table
  .text('user_id', (col) => col.notNull())
  .integer('sequence', (col) => col.notNull())
  .key(['user_id', 'sequence']).primary()
```

### Foreign Keys

```dart
table
  .integer('user_id', (col) => col.notNull())
  .foreignKey('user_id').references('users', 'id')

// Composite foreign key
table
  .text('user_id', (col) => col.notNull())
  .integer('sequence', (col) => col.notNull())
  .foreignKey(['user_id', 'sequence'])
    .references('user_sequences', ['user_id', 'sequence'])
```

### Unique Constraints

```dart
// Single column unique
table.text('email', (col) => col.unique())

// Composite unique constraint
table
  .text('username')
  .text('domain')
  .unique(['username', 'domain'])
```

### Check Constraints

```dart
table
  .integer('age', (col) => col
    .min(0)                          // age >= 0
    .max(150))                       // age <= 150
  .real('price', (col) => col
    .min(0.0))                       // price >= 0.0
```

## Indices

### Simple Indices

```dart
schema
  .table('posts', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('title')
    .text('content')
    .integer('user_id')
    .date('created_at'))
  .index('posts', ['user_id'])        // Single column index
  .index('posts', ['created_at'])     // Date index for sorting
```

### Composite Indices

```dart
schema
  .index('posts', ['user_id', 'created_at'])  // Composite index
  .index('posts', ['title', 'user_id'])       // For search queries
```

### Unique Indices

```dart
schema
  .uniqueIndex('users', ['email'])             // Unique email
  .uniqueIndex('posts', ['user_id', 'slug'])   // Unique slug per user
```

### Partial Indices

```dart
schema
  .index('posts', ['published_at'])
    .where('published_at IS NOT NULL')         // Only index published posts
```

## SQL Views

Create computed views for complex queries:

### Basic Views

```dart
schema
  .view('user_stats', (view) => view
    .select('u.id', 'user_id')
    .select('u.username')
    .selectSubQuery((sub) => sub
      .count()
      .from('posts', 'p')
      .where('p.user_id = u.id'), 'post_count')
    .from('users', 'u'))
```

### Views with Joins

```dart
schema
  .view('post_details', (view) => view
    .select('p.id')
    .select('p.title')
    .select('p.content')
    .select('u.username', 'author')
    .select('p.created_at')
    .from('posts', 'p')
    .innerJoin('users', 'u', 'p.user_id = u.id')
    .where('p.published = 1'))
```

### Aggregated Views

```dart
schema
  .view('monthly_stats', (view) => view
    .select("strftime('%Y-%m', created_at)", 'month')
    .selectCount('*', 'post_count')
    .selectSum('view_count', 'total_views')
    .from('posts')
    .where('published = 1')
    .groupBy("strftime('%Y-%m', created_at)"))
```

## Advanced Schema Features

### Last-Write-Wins (LWW) Columns

For conflict resolution in sync scenarios:

```dart
table
  .text('title', (col) => col.lww())         // LWW enabled
  .integer('score', (col) => col.lww())      // Automatic conflict resolution
```

### Soft Delete Support

```dart
table
  .date('deleted_at')                        // Soft delete timestamp
  
// The library will automatically filter out soft-deleted records
```

### Timestamps

```dart
table
  .timestamps()                              // Adds created_at and updated_at
  
// Equivalent to:
// .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
// .date('updated_at', (col) => col.notNull().defaultValue(DateTime.now()))
```

## Schema Validation

The library automatically validates your schema definition:

```dart
// This will throw a validation error:
final invalidSchema = SchemaBuilder()
  .table('users', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('email', (col) => col.notNull().unique())
    .foreignKey('email').references('nonexistent_table', 'id')) // Error!
```

## Complete Example

Here's a comprehensive schema for a blog application:

```dart
final blogSchema = SchemaBuilder()
  // Users table
  .table('users', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('username', (col) => col.notNull().unique().maxLength(50))
    .text('email', (col) => col.notNull().unique().maxLength(255))
    .text('full_name', (col) => col.maxLength(100))
    .text('bio', (col) => col.maxLength(500))
    .text('avatar_url')
    .boolean('is_active', (col) => col.notNull().defaultValue(true))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('last_login'))
  
  // Categories table
  .table('categories', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('name', (col) => col.notNull().unique().maxLength(100))
    .text('slug', (col) => col.notNull().unique().maxLength(100))
    .text('description')
    .integer('sort_order', (col) => col.defaultValue(0)))
  
  // Posts table
  .table('posts', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('title', (col) => col.notNull().maxLength(200))
    .text('slug', (col) => col.notNull().maxLength(200))
    .text('content', (col) => col.notNull())
    .text('excerpt', (col) => col.maxLength(500))
    .integer('user_id', (col) => col.notNull())
    .integer('category_id')
    .boolean('published', (col) => col.notNull().defaultValue(false))
    .integer('view_count', (col) => col.notNull().defaultValue(0))
    .fileset('attachments')
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('updated_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('published_at')
    .foreignKey('user_id').references('users', 'id')
    .foreignKey('category_id').references('categories', 'id'))
  
  // Comments table
  .table('comments', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('content', (col) => col.notNull().maxLength(1000))
    .integer('post_id', (col) => col.notNull())
    .integer('user_id', (col) => col.notNull())
    .integer('parent_id')  // For nested comments
    .boolean('approved', (col) => col.notNull().defaultValue(false))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .foreignKey('post_id').references('posts', 'id')
    .foreignKey('user_id').references('users', 'id')
    .foreignKey('parent_id').references('comments', 'id'))
  
  // Indices for performance
  .index('posts', ['user_id', 'published'])
  .index('posts', ['category_id'])
  .index('posts', ['published_at'])
  .index('posts', ['slug'])
  .index('comments', ['post_id', 'approved'])
  .index('comments', ['user_id'])
  .uniqueIndex('users', ['email'])
  .uniqueIndex('posts', ['slug'])
  
  // Views for common queries
  .view('published_posts', (view) => view
    .select('p.*')
    .select('u.username', 'author')
    .select('c.name', 'category_name')
    .from('posts', 'p')
    .leftJoin('users', 'u', 'p.user_id = u.id')
    .leftJoin('categories', 'c', 'p.category_id = c.id')
    .where('p.published = 1'))
    
  .view('user_post_counts', (view) => view
    .select('u.id', 'user_id')
    .select('u.username')
    .selectCount('p.id', 'post_count')
    .from('users', 'u')
    .leftJoin('posts', 'p', 'u.id = p.user_id AND p.published = 1')
    .groupBy('u.id', 'u.username'));
```

## Next Steps

Now that you understand schema definition:

- Learn about [Database Operations](./database-operations)
- Explore [Streaming Queries](./streaming-queries)
- Set up [Code Generation](../generator/setup) for type-safe data classes
- See [Migration](./migration) for handling schema changes