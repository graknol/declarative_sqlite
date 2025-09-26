# DeclarativeDatabase Current State Documentation

## Overview

DeclarativeDatabase is a SQLite abstraction layer that provides type-safe database operations with real-time streaming queries, dirty row tracking for synchronization, and Last-Write-Wins (LWW) conflict resolution.

## Core Features

### Database Operations

#### Basic CRUD Operations
```dart
final db = DeclarativeDatabase.open('database.db', schemaBuilder);

// Insert
final systemId = await db.insert('users', {
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30,
});

// Update
final rowsUpdated = await db.update(
  'users', 
  {'age': 31},
  where: 'name = ?',
  whereArgs: ['John Doe'],
);

// Delete
final rowsDeleted = await db.delete(
  'users',
  where: 'age > ?',
  whereArgs: [65],
);

// Query
final users = await db.queryMaps((q) => q
  .from('users')
  .where(RawSqlWhereClause('age > ?', [18]))
);
```

#### System Columns
Every record automatically includes system columns:
- `system_id`: UUID primary key for internal tracking
- `system_created_at`: HLC timestamp of creation
- `system_version`: HLC timestamp of last modification

#### Raw SQL Operations
```dart
// Raw insert
await db.rawInsert('INSERT INTO users (name, age) VALUES (?, ?)', ['Jane', 25]);

// Raw update
await db.rawUpdate('UPDATE users SET age = age + 1 WHERE age < ?', [30]);

// Raw delete
await db.rawDelete('DELETE FROM users WHERE age > ?', [65]);

// Raw query
final results = await db.rawQuery('SELECT name, COUNT(*) as count FROM users GROUP BY name');
```

### Streaming Queries

Real-time reactive queries that emit new results when underlying data changes:

```dart
// Basic streaming query
final userStream = db.stream<Map<String, Object?>>(
  (q) => q.from('users').where(RawSqlWhereClause('age >= ?', [18])),
  (row) => row,
);

userStream.listen((users) {
  print('Active users: ${users.length}');
  for (final user in users) {
    print('${user['name']} - ${user['age']} years old');
  }
});

// Typed streaming query with DbRecord
final typedStream = db.streamTyped<User>((q) => q.from('users'));
typedStream.listen((users) {
  for (final user in users) {
    print('User: ${user.name} (${user.email})');
  }
});
```

#### How Streaming Works
- Queries automatically track dependencies on tables and columns
- Changes to relevant data trigger re-execution and emission of updated results  
- Initial result is emitted immediately upon subscription
- Streams clean up automatically when all listeners unsubscribe

### Schema Definition

```dart
void buildSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id');           // User-defined primary key
    table.text('name');
    table.integer('age');
    table.text('email');
    table.datetime('created_at');
  });
  
  builder.table('posts', (table) {
    table.guid('id');
    table.text('title');
    table.text('content').lww();  // Last-Write-Wins column
    table.guid('user_id');
    table.datetime('published_at');
  });
  
  builder.table('tags', (table) {
    table.guid('id');
    table.text('name').lww();        // LWW column
    table.text('description').lww(); // LWW column
  });
}
```

#### Column Types
- `guid()`: Text UUID column
- `text()`: Text/string column  
- `integer()`: Integer column
- `real()`: Floating point column
- `datetime()`: DateTime stored as ISO string
- `blob()`: Binary data column
- `fileset()`: File attachment column

#### Column Modifiers
- `.lww()`: Marks column as Last-Write-Wins for conflict resolution
- `.notNull()`: Adds NOT NULL constraint (requires default value or callback)

### Last-Write-Wins (LWW) Columns

LWW columns automatically handle conflict resolution in distributed systems:

```dart
// When you update an LWW column, it gets a timestamp
await db.update('posts', {
  'content': 'Updated content',  // This will get content__hlc timestamp
});

// Query results include both value and timestamp
final posts = await db.queryMaps((q) => q.from('posts'));
final post = posts.first;
print('Content: ${post['content']}');
print('Last modified: ${post['content__hlc']}'); // HLC timestamp
```

### Dirty Row Tracking

Tracks all modifications for synchronization with external systems:

```dart
// All insert/update/delete operations create dirty row entries
await db.insert('users', {'name': 'John'});
await db.update('users', {'age': 25}, where: 'name = ?', whereArgs: ['John']);

// Get dirty rows for sync
final dirtyRows = await db.getDirtyRows();
for (final dirty in dirtyRows) {
  print('Table: ${dirty.tableName}');
  print('System ID: ${dirty.systemId}'); 
  print('HLC: ${dirty.hlc}');
  print('Operation: ${dirty.operation}'); // INSERT, UPDATE, DELETE
}

// Bulk operations don't create dirty rows (for data import)
await db.bulkLoad('users', [
  {'name': 'Alice', 'age': 30},
  {'name': 'Bob', 'age': 25},
]);
```

### Database Management

```dart
// Open database with schema
final db = DeclarativeDatabase.open('path/to/database.db', buildSchema);

// Memory database for testing
final testDb = DeclarativeDatabase.memory(buildSchema);

// Close database
await db.close();

// Check if database is open
if (db.isOpen) {
  // Database is ready for operations
}
```

## Important Limitations

### No Transaction Support

**Transactions are explicitly NOT supported** and will throw `UnsupportedError`:

```dart
// This will throw UnsupportedError
try {
  await db.transaction((txn) async {
    await txn.insert('users', {'name': 'John'});
    await txn.insert('posts', {'title': 'My Post'});
  });
} catch (e) {
  // UnsupportedError: Transactions are not supported in DeclarativeDatabase...
}
```

**Why transactions are disabled:**
- Complexity with dirty row rollbacks during transaction failures
- Interaction with real-time streaming queries and change notifications
- Edge cases with LWW timestamp consistency
- State management complexity across transaction boundaries

**Alternative approaches:**
- Use separate database operations and handle consistency at the application level
- Implement compensating actions for rollback scenarios
- Use bulk operations where atomicity isn't required

## Error Handling

```dart
try {
  await db.insert('users', {'name': 'John'});
} catch (e) {
  if (e is DbCreateException) {
    print('Failed to create record: ${e.message}');
  } else if (e is UnsupportedError) {
    print('Operation not supported: ${e.message}');
  }
}
```

## Testing Support

The package provides excellent testing support with in-memory databases:

```dart
import 'package:test/test.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  late DeclarativeDatabase database;

  setUp(() async {
    database = DeclarativeDatabase.memory(buildTestSchema);
  });

  tearDown(() async {
    await database.close();
  });

  test('user operations work correctly', () async {
    // Test database operations
    final userId = await database.insert('users', {
      'name': 'John Doe',
      'age': 30,
    });
    
    expect(userId, isA<String>());
    
    final users = await database.queryMaps((q) => q.from('users'));
    expect(users.length, equals(1));
    expect(users.first['name'], equals('John Doe'));
  });
}
```

## Performance Considerations

- **Streaming Queries**: Use precise query builders to minimize unnecessary re-executions
- **Dirty Row Tracking**: Regularly clean up processed dirty rows to prevent table growth
- **LWW Columns**: Only use on columns that actually need conflict resolution
- **Bulk Operations**: Use `bulkLoad` for importing large datasets to avoid dirty row overhead

## Migration and Schema Evolution

Schema changes should be handled through database migration scripts:

```dart
// Version your schema builder
void buildSchemaV1(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id');
    table.text('name');
  });
}

void buildSchemaV2(SchemaBuilder builder) {
  buildSchemaV1(builder);  // Include previous version
  
  // Add new table in V2
  builder.table('posts', (table) {
    table.guid('id');
    table.text('title');
    table.guid('user_id');
  });
}
```

## Best Practices

1. **Always handle system columns**: Remember that `system_id` is the internal primary key
2. **Use appropriate column types**: Choose LWW only when needed for conflict resolution
3. **Stream query optimization**: Write specific queries to avoid unnecessary re-executions
4. **Error handling**: Always wrap database operations in try-catch blocks
5. **Memory management**: Close databases when done, especially in tests
6. **Dirty row cleanup**: Implement periodic cleanup of processed dirty rows
7. **Schema design**: Plan your schema carefully as transaction rollbacks aren't available

## Migration from Transaction-Based Code

If you have existing code using transactions, refactor as follows:

**Instead of:**
```dart
// DON'T DO THIS - Will throw UnsupportedError
await db.transaction((txn) async {
  await txn.insert('users', userData);
  await txn.insert('posts', postData);
});
```

**Do this:**
```dart
// Use separate operations with error handling
try {
  final userId = await db.insert('users', userData);
  
  // Add user ID to post data
  postData['user_id'] = userId;
  await db.insert('posts', postData);
} catch (e) {
  // Handle errors and implement compensating actions if needed
  // For example: delete the user if post creation fails
}
```

This design prioritizes simplicity, reliability, and real-time capabilities over traditional ACID transaction semantics.