# Exception Handling

Declarative SQLite provides a comprehensive exception handling system that wraps platform-specific database exceptions into developer-friendly types, similar to REST API status codes.

## Overview

Instead of catching various platform-specific exceptions like `DatabaseException`, `SQLiteException`, etc., you can now catch well-defined exception types that map to business operations:

```dart
try {
  await user.save();
} on DbUpdateException catch (e) {
  // Handle record update failures
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      showUserFriendlyError('Email already exists');
      break;
    case DbErrorCategory.concurrencyConflict:
      await user.reload(); // Reload and retry
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

```
DbException
├── DbCreateException      (POST-like operations)
├── DbReadException        (GET-like operations)  
├── DbUpdateException      (PUT/PATCH-like operations)
├── DbDeleteException      (DELETE-like operations)
└── DbQueryException       (Complex query operations)
```

### Base DbException

All database exceptions provide:

```dart
abstract class DbException implements Exception {
  final String message;
  final DbErrorCategory errorCategory;
  final Map<String, dynamic> context;
  final Exception? innerException;
  
  // ... implementation
}
```

### DbCreateException

Thrown when creating new records fails:

```dart
try {
  await db.insert('users', userData);
  // or
  await newUser.save();
} on DbCreateException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      // Primary key conflict, unique constraint violation, etc.
      handleDuplicateUser(e.context);
      break;
    case DbErrorCategory.invalidData:
      // Data validation failed
      showValidationErrors(e.context);
      break;
    case DbErrorCategory.storageFailure:
      // Disk full, permission issues, etc.
      handleStorageIssue();
      break;
  }
}
```

### DbUpdateException

Thrown when updating existing records fails:

```dart
try {
  user.name = 'New Name';
  await user.save();
} on DbUpdateException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.recordNotFound:
      // Record was deleted by another process
      handleDeletedRecord();
      break;
    case DbErrorCategory.concurrencyConflict:
      // LWW version conflict
      await user.reload();
      showConflictResolution();
      break;
    case DbErrorCategory.constraintViolation:
      // Foreign key constraint, check constraint, etc.
      handleConstraintViolation(e.context);
      break;
  }
}
```

### DbDeleteException

Thrown when deleting records fails:

```dart
try {
  await user.delete();
} on DbDeleteException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.recordNotFound:
      // Record already deleted
      refreshUI();
      break;
    case DbErrorCategory.constraintViolation:
      // Foreign key prevents deletion
      showDependentRecordsDialog(e.context);
      break;
    case DbErrorCategory.concurrencyConflict:
      // Someone else modified the record
      await user.reload();
      confirmDeletion();
      break;
  }
}
```

### DbReadException

Thrown when reading data fails:

```dart
try {
  final users = await db.queryTyped<User>((q) => q.from('users'));
} on DbReadException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.invalidQuery:
      // SQL syntax error, invalid table name, etc.
      logInvalidQuery(e.context);
      break;
    case DbErrorCategory.storageFailure:
      // Database file corrupted, permission denied, etc.
      handleDatabaseCorruption();
      break;
    case DbErrorCategory.resourceExhausted:
      // Out of memory, too many connections, etc.
      handleResourceExhaustion();
      break;
  }
}
```

### DbQueryException

Thrown when complex query operations fail:

```dart
try {
  final result = await db.queryTyped<UserStats>((q) => 
    q.from('users u')
     .join('posts p', 'p.user_id = u.id')
     .where('p.created_at > ?', [complexDate])
  );
} on DbQueryException catch (e) {
  switch (e.errorCategory) {
    case DbErrorCategory.invalidQuery:
      // Complex join failed, invalid SQL, etc.
      handleQueryError(e.context);
      break;
    case DbErrorCategory.timeout:
      // Query took too long
      handleQueryTimeout();
      break;
  }
}
```

## Error Categories

The `DbErrorCategory` enum provides business-focused error categorization:

### Data-Related Errors

```dart
enum DbErrorCategory {
  // Data validation and constraints
  invalidData,           // Data doesn't meet validation rules
  constraintViolation,   // Primary key, foreign key, unique, check constraints
  
  // Record state issues  
  recordNotFound,        // Record doesn't exist
  concurrencyConflict,   // LWW version mismatch, optimistic locking
  
  // Query and schema issues
  invalidQuery,          // SQL syntax error, invalid table/column names
  
  // System and resource issues
  storageFailure,        // Disk full, file corruption, permissions
  resourceExhausted,     // Memory, connections, locks
  timeout,               // Operation timed out
  
  // Network and sync issues (for future sync features)
  networkFailure,        // Connection issues
  authenticationFailure, // Authentication/authorization failed
  
  // Unknown platform errors
  unknown,               // Unrecognized platform exception
}
```

### Usage Examples

```dart
void handleDatabaseError(DbException e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      showMessage('The data violates database rules');
      break;
    case DbErrorCategory.concurrencyConflict:
      showMessage('Someone else modified this record. Please refresh and try again.');
      break;
    case DbErrorCategory.storageFailure:
      showMessage('Database storage issue. Please check disk space.');
      break;
    case DbErrorCategory.networkFailure:
      showMessage('Network connection failed. Please check your internet.');
      break;
    default:
      showMessage('An unexpected error occurred: ${e.message}');
  }
}
```

## Exception Context

Exceptions provide rich context information for better error handling:

```dart
try {
  await user.save();
} on DbUpdateException catch (e) {
  print('Error: ${e.message}');
  print('Category: ${e.errorCategory}');
  print('Context: ${e.context}');
  
  // Context might include:
  // {
  //   'table': 'users',
  //   'operation': 'update',
  //   'conflictingFields': ['email'],
  //   'constraintName': 'unique_email',
  //   'sql': 'UPDATE users SET email = ? WHERE id = ?',
  //   'parameters': ['test@example.com', 'user-123']
  // }
  
  if (e.context['constraintName'] == 'unique_email') {
    showMessage('Email address is already in use');
  }
}
```

## Platform Exception Mapping

The exception system automatically maps platform-specific exceptions:

### SQLite Exceptions

```dart
// SQLite UNIQUE constraint violation
// Maps to: DbUpdateException with DbErrorCategory.constraintViolation

// SQLite FOREIGN KEY constraint violation  
// Maps to: DbCreateException/DbUpdateException with DbErrorCategory.constraintViolation

// SQLite syntax error
// Maps to: DbQueryException with DbErrorCategory.invalidQuery

// SQLite database locked
// Maps to: DbException with DbErrorCategory.resourceExhausted
```

### File System Exceptions

```dart
// Permission denied
// Maps to: DbException with DbErrorCategory.storageFailure

// Disk full
// Maps to: DbException with DbErrorCategory.storageFailure

// File not found (for database files)
// Maps to: DbException with DbErrorCategory.storageFailure
```

## Best Practices

### 1. Catch Specific Exception Types

```dart
// ✅ Good: Catch specific exception types
try {
  await user.save();
} on DbUpdateException catch (e) {
  handleUpdateError(e);
} on DbCreateException catch (e) {
  handleCreateError(e);
} on DbException catch (e) {
  handleGenericDatabaseError(e);
}

// ❌ Avoid: Catching only the base exception
try {
  await user.save();
} on DbException catch (e) {
  // Less specific handling
}
```

### 2. Use Error Categories for Business Logic

```dart
// ✅ Good: Use error categories for business decisions
void handleUserSaveError(DbException e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      if (e.context['constraintName']?.contains('email') == true) {
        showEmailAlreadyExistsDialog();
      } else {
        showGenericConstraintError();
      }
      break;
    case DbErrorCategory.concurrencyConflict:
      showRefreshAndRetryDialog();
      break;
    default:
      showGenericError(e.message);
  }
}
```

### 3. Provide User-Friendly Messages

```dart
// ✅ Good: Translate technical errors to user-friendly messages
String getUserFriendlyMessage(DbException e) {
  switch (e.errorCategory) {
    case DbErrorCategory.constraintViolation:
      return 'The information you entered conflicts with existing data';
    case DbErrorCategory.concurrencyConflict:
      return 'Someone else modified this record. Please refresh and try again';
    case DbErrorCategory.storageFailure:
      return 'Unable to save data. Please check available storage space';
    case DbErrorCategory.networkFailure:
      return 'Connection failed. Please check your internet connection';
    default:
      return 'An unexpected error occurred. Please try again';
  }
}
```

### 4. Log Technical Details

```dart
// ✅ Good: Log technical details while showing user-friendly messages
try {
  await user.save();
} on DbException catch (e) {
  // Log technical details for debugging
  logger.error('Database operation failed', {
    'exception': e.runtimeType.toString(),
    'category': e.errorCategory.toString(),
    'message': e.message,
    'context': e.context,
    'innerException': e.innerException?.toString(),
  });
  
  // Show user-friendly message
  showSnackBar(getUserFriendlyMessage(e));
}
```

### 5. Handle Retryable Errors

```dart
// ✅ Good: Implement retry logic for appropriate error types
Future<void> saveUserWithRetry(User user, {int maxRetries = 3}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      await user.save();
      return; // Success
    } on DbUpdateException catch (e) {
      if (e.errorCategory == DbErrorCategory.concurrencyConflict && attempt < maxRetries) {
        // Reload and retry for concurrency conflicts
        await user.reload();
        await Future.delayed(Duration(milliseconds: 100 * attempt)); // Exponential backoff
        continue;
      }
      rethrow; // Don't retry for other errors or if max retries reached
    }
  }
}
```

## Testing Exception Handling

```dart
// Test exception handling in your code
void testExceptionHandling() {
  test('should handle constraint violations gracefully', () async {
    final user1 = User.create(db);
    user1.email = 'test@example.com';
    await user1.save();
    
    final user2 = User.create(db);
    user2.email = 'test@example.com'; // Duplicate email
    
    expect(
      () => user2.save(),
      throwsA(isA<DbCreateException>()
        .having((e) => e.errorCategory, 'errorCategory', 
               equals(DbErrorCategory.constraintViolation))),
    );
  });
}
```

## Next Steps

Now that you understand exception handling, explore:

- [Typed Records](typed-records) - Working with typed database records  
- [Advanced Features](advanced-features) - Garbage collection and other utilities
- [Streaming Queries](streaming-queries) - Real-time data updates