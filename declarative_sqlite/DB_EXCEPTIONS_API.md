# Database Exception Handling

The DeclarativeDatabase provides a comprehensive exception handling system that wraps platform-specific database exceptions into developer-friendly types, similar to REST API status codes. This makes it easy to handle different types of database failures in a consistent, business-focused way.

## Overview

Instead of catching various platform-specific exceptions like `DatabaseException`, `SQLiteException`, etc., you can now catch well-defined exception types that map to business operations:

```dart
try {
  await db.insert('users', userData);
} on DbCreateException catch (e) {
  // Handle record creation failures
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      showUserFriendlyError('Email already exists');
      break;
    case DbErrorCategory.invalidData:
      showValidationErrors(e.context);
      break;
  }
} on DbException catch (e) {
  // Handle any other database error
  logError('Database operation failed', e);
}
```

## Exception Hierarchy

All database exceptions extend the base `DbException` class:

```dart
abstract class DbException implements Exception {
  final DbOperationType operationType;    // What operation failed
  final DbErrorCategory errorCategory;     // Why it failed  
  final String message;                    // Human-readable message
  final String? tableName;                 // Related table
  final String? columnName;                // Related column
  final Exception? originalException;      // Original platform exception
  final Map<String, Object?>? context;     // Additional context
}
```

## Exception Types by Business Operation

### DbCreateException - "Can't create the record"

Thrown when insert operations fail:

```dart
try {
  await db.insert('users', {
    'id': 1,
    'email': 'user@example.com',
    'name': 'John Doe',
  });
} on DbCreateException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      // Primary key, unique, foreign key violations
      handleConstraintViolation(e);
      break;
    case DbErrorCategory.invalidData:
      // Data type mismatches, invalid values
      handleInvalidData(e);
      break;
  }
}
```

**Common Factory Methods:**
- `DbCreateException.constraintViolation()` - Constraint violations
- `DbCreateException.invalidData()` - Invalid data types or values

### DbReadException - "Can't read the record"

Thrown when query operations fail:

```dart
try {
  final users = await db.queryTable('users');
} on DbReadException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.notFound:
      // Table, view, or specific records not found
      handleNotFound(e);
      break;
    case DbErrorCategory.accessDenied:
      // Permission or security issues
      handleAccessDenied(e);
      break;
  }
}
```

**Common Factory Methods:**
- `DbReadException.notFound()` - Resource not found
- `DbReadException.accessDenied()` - Access permission issues

### DbUpdateException - "Can't update the record"

Thrown when update operations fail:

```dart
try {
  await db.update('users', {'age': 31}, where: 'id = ?', whereArgs: [1]);
} on DbUpdateException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      // Constraint violations during update
      handleConstraintViolation(e);
      break;
    case DbErrorCategory.concurrencyConflict:
      // Optimistic locking failures
      handleConcurrencyConflict(e);
      break;
    case DbErrorCategory.notFound:
      // Record to update doesn't exist
      handleRecordNotFound(e);
      break;
  }
}
```

**Common Factory Methods:**
- `DbUpdateException.constraintViolation()` - Constraint violations
- `DbUpdateException.concurrencyConflict()` - Version conflicts
- `DbUpdateException.notFound()` - Record not found

### DbDeleteException - "Can't delete the record"

Thrown when delete operations fail:

```dart
try {
  await db.delete('users', where: 'id = ?', whereArgs: [1]);
} on DbDeleteException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      // Foreign key constraints preventing deletion
      handleForeignKeyConstraint(e);
      break;
    case DbErrorCategory.notFound:
      // Record to delete doesn't exist
      handleRecordNotFound(e);
      break;
  }
}
```

**Common Factory Methods:**
- `DbDeleteException.constraintViolation()` - Foreign key constraints
- `DbDeleteException.notFound()` - Record not found

### DbTransactionException - "Transaction failed"

Thrown when transaction operations fail:

```dart
try {
  await db.transaction((txn) async {
    await txn.insert('users', userData);
    await txn.insert('profiles', profileData);
  });
} on DbTransactionException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.databaseLocked:
      // Database is locked or busy
      retryLater();
      break;
    case DbErrorCategory.concurrencyConflict:
      // Transaction conflicts
      handleConflict(e);
      break;
  }
}
```

**Common Factory Methods:**
- `DbTransactionException.rollback()` - Transaction rolled back
- `DbTransactionException.databaseLocked()` - Database locked

### DbConnectionException - "Database connection issues"

Thrown when connection operations fail:

```dart
try {
  final db = await DeclarativeDatabase.open('database.db', schema: schema);
} on DbConnectionException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.connectionError:
      // Connection failures
      handleConnectionFailure(e);
      break;
    case DbErrorCategory.corruption:
      // Database file corruption
      handleCorruption(e);
      break;
  }
}
```

**Common Factory Methods:**
- `DbConnectionException.connectionFailed()` - Connection failures
- `DbConnectionException.corruption()` - Database corruption

### DbMigrationException - "Schema migration problems"

Thrown when migration operations fail:

```dart
try {
  final db = await DeclarativeDatabase.open('database.db', schema: newSchema);
} on DbMigrationException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.schemaMismatch:
      // Schema migration failures
      handleMigrationFailure(e);
      break;
  }
}
```

**Common Factory Methods:**
- `DbMigrationException.schemaMismatch()` - Schema migration issues

## Error Categories

Each exception includes an `errorCategory` that provides more specific information about the failure:

| Category | Description | Common Causes |
|----------|-------------|---------------|
| `constraintViolation` | Constraint violations | Primary key, unique, foreign key, check constraints |
| `notFound` | Resource not found | Table, column, or record doesn't exist |
| `invalidData` | Invalid data or operation | Data type mismatch, invalid values, SQL syntax errors |
| `accessDenied` | Permission or access denied | Security restrictions, read-only database |
| `databaseLocked` | Database is locked or busy | Concurrent access, long-running operations |
| `connectionError` | Connection issues | Network problems, file access issues |
| `corruption` | Database corruption | File corruption, disk errors |
| `schemaMismatch` | Schema mismatch or migration issues | Migration failures, version conflicts |
| `concurrencyConflict` | Concurrency conflict | Optimistic locking, transaction conflicts |
| `unknown` | Unknown or unexpected error | Unclassified platform errors |

## DbRecord Exception Integration

DbRecord operations automatically benefit from exception wrapping:

```dart
try {
  final users = await db.queryTyped<User>((q) => q.from('users'));
  final user = users.first;
  
  user.email = 'newemail@example.com';
  await user.save(); // Automatically wrapped
} on DbUpdateException catch (e) {
  if (e.errorCategory == DbErrorCategory.constraintViolation) {
    showError('Email already exists');
  }
} on DbException catch (e) {
  showError('Database error: ${e.message}');
}
```

## Exception Context and Details

Exceptions provide rich context information:

```dart
catch (e) {
  if (e is DbException) {
    print('Operation: ${e.operationType}');      // create, read, update, delete
    print('Category: ${e.errorCategory}');        // constraintViolation, notFound, etc.
    print('Message: ${e.message}');               // Human-readable message
    print('Table: ${e.tableName}');               // Related table (if any)
    print('Column: ${e.columnName}');             // Related column (if any)
    print('Original: ${e.originalException}');    // Platform exception
    print('Context: ${e.context}');               // Additional context data
  }
}
```

### Context Information

The `context` map can include additional details:

```dart
final exception = DbCreateException.constraintViolation(
  message: 'Email must be unique',
  tableName: 'users',
  columnName: 'email',
  context: {
    'attempted_value': 'user@example.com',
    'constraint_type': 'unique',
    'existing_record_id': 123,
  },
);
```

## Best Practices

### 1. Handle Specific Exception Types

```dart
try {
  await databaseOperation();
} on DbCreateException catch (e) {
  // Handle create-specific failures
  handleCreateFailure(e);
} on DbUpdateException catch (e) {
  // Handle update-specific failures
  handleUpdateFailure(e);
} on DbException catch (e) {
  // Handle any other database error
  handleGeneralDatabaseError(e);
} catch (e) {
  // Handle unexpected errors
  handleUnexpectedError(e);
}
```

### 2. Use Error Categories for Business Logic

```dart
void handleDatabaseException(DbException e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      showUserFriendlyConstraintError(e);
      break;
    case DbErrorCategory.notFound:
      redirectToNotFoundPage();
      break;
    case DbErrorCategory.databaseLocked:
      showRetryDialog();
      break;
    case DbErrorCategory.accessDenied:
      redirectToLoginPage();
      break;
    default:
      showGenericErrorMessage(e.message);
  }
}
```

### 3. Log Original Exceptions for Debugging

```dart
catch (e) {
  if (e is DbException) {
    // Log original platform exception for debugging
    logger.error('Database ${e.operationType} failed', e.originalException);
    
    // Show user-friendly message
    showUserMessage(e.message);
  }
}
```

### 4. Provide Context in Custom Exceptions

```dart
try {
  await db.insert('orders', orderData);
} on DbCreateException catch (e) {
  throw OrderCreationException(
    'Failed to create order #${orderData['order_number']}',
    originalException: e,
    orderData: orderData,
  );
}
```

### 5. Retry Logic for Transient Errors

```dart
Future<T> retryDatabaseOperation<T>(Future<T> Function() operation) async {
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      return await operation();
    } on DbException catch (e) {
      if (e.errorCategory == DbErrorCategory.databaseLocked && attempt < 3) {
        await Future.delayed(Duration(milliseconds: 100 * attempt));
        continue;
      }
      rethrow;
    }
  }
  throw StateError('Should not reach here');
}
```

## Migration from Platform Exceptions

### Before: Platform-Specific Handling

```dart
try {
  await db.insert('users', userData);
} on DatabaseException catch (e) {
  if (e.toString().contains('UNIQUE constraint failed')) {
    // Handle unique constraint
  } else if (e.toString().contains('FOREIGN KEY constraint failed')) {
    // Handle foreign key constraint
  } else {
    // Generic handling
  }
} on SqliteException catch (e) {
  // Different exception type with different API
} catch (e) {
  // Could be any number of platform exceptions
}
```

### After: Business-Focused Handling

```dart
try {
  await db.insert('users', userData);
} on DbCreateException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      handleConstraintViolation(e); // Covers all constraint types
      break;
    default:
      handleOtherCreateErrors(e);
  }
} on DbException catch (e) {
  handleAnyDatabaseError(e); // Consistent API across all DB operations
}
```

## Exception Mapping Details

The system automatically maps platform exceptions to appropriate `DbException` types:

- **SQLite constraint errors** → `DbCreateException.constraintViolation()`
- **Table not found errors** → `DbReadException.notFound()`
- **Database locked errors** → `DbTransactionException.databaseLocked()`
- **File corruption errors** → `DbConnectionException.corruption()`
- **All other errors** → Appropriate exception type based on operation and error content

This provides a consistent, REST API-like experience where you handle database errors by their business impact rather than their technical implementation details.