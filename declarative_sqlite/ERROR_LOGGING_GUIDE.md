# Error Logging Integration Guide

The `declarative_sqlite` library provides comprehensive error logging hooks that allow developers to integrate with their preferred error logging solutions like Sentry, Azure Application Insights, Firebase Crashlytics, or any custom logging system.

## Overview

The error logging system captures two types of errors:

1. **Sync Manager Errors**: Related to `ServerSyncManager` operations (network failures, server errors, retry logic, etc.)
2. **Database Core Library Errors**: Related to core database operations (SQL execution, migrations, data access, etc.)

## Quick Setup

### Basic Console Logging (Development)

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

// Enable console logging for development
ErrorLoggerHelpers.configureConsoleLogging(includeStackTrace: true);
```

### Sentry Integration (Production)

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sentry/sentry.dart';

// Configure Sentry error logging
ErrorLoggerHelpers.configureSentry((error, context, stackTrace) {
  Sentry.captureException(error, stackTrace: stackTrace, withScope: (scope) {
    scope.setTag('error_type', context.type.name);
    scope.setTag('severity', context.severity.name);
    scope.setTag('operation', context.operation);
    scope.setTag('table_name', context.tableName ?? 'unknown');
    
    // Add custom context
    scope.setContext('sqlite_error', {
      'operation': context.operation,
      'table': context.tableName,
      'additional_data': context.additionalData,
    });
  });
});
```

### Azure Application Insights Integration

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';
// import your Azure App Insights package

ErrorLoggerHelpers.configureAzureAppInsights((error, context, stackTrace) {
  appInsights.trackException(error, properties: {
    'error_type': context.type.name,
    'severity': context.severity.name,
    'operation': context.operation,
    'table_name': context.tableName ?? 'unknown',
    'stack_trace': stackTrace?.toString(),
    ...context.additionalData,
  });
});
```

## Advanced Configuration

### Separate Handlers for Different Error Types

```dart
// Configure sync manager error logging
ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
  if (context.severity == ErrorSeverity.critical) {
    // Send critical sync errors to incident management
    PagerDuty.triggerIncident({
      'title': 'Critical Sync Error: ${context.operation}',
      'details': error.toString(),
      'context': context.additionalData,
    });
  } else {
    // Log to standard monitoring
    AppInsights.trackException(error, properties: context.additionalData);
  }
});

// Configure database error logging
ErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
  // Database errors always go to detailed logging
  Sentry.captureException(error, stackTrace: stackTrace, withScope: (scope) {
    scope.setLevel(SentryLevel.error);
    scope.setTag('component', 'database');
    scope.setTag('table', context.tableName ?? 'unknown');
    scope.setContext('database_operation', context.additionalData);
  });
});
```

### Custom Error Filtering and Enrichment

```dart
ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
  // Skip logging for certain temporary network errors
  if (error.toString().contains('connection timeout') && 
      context.severity == ErrorSeverity.info) {
    return;
  }
  
  // Enrich context with user information
  final enrichedData = {
    ...context.additionalData,
    'user_id': getCurrentUserId(),
    'app_version': getAppVersion(),
    'device_info': getDeviceInfo(),
  };
  
  // Log to your preferred service
  MyLogger.error('Sync Error: ${context.operation}', {
    'error': error.toString(),
    'severity': context.severity.name,
    'context': enrichedData,
    'stack_trace': stackTrace?.toString(),
  });
});
```

## Error Context Information

Each error callback receives:

- `error`: The actual error/exception that occurred
- `context`: An `ErrorContext` object with structured information
- `stackTrace`: Stack trace if available (may be null in some cases)

### ErrorContext Properties

```dart
class ErrorContext {
  final ErrorType type;           // syncManager or database
  final ErrorSeverity severity;   // info, warning, error, critical
  final String operation;         // Specific operation that failed
  final String? tableName;        // Table involved (if applicable)
  final Map<String, dynamic> additionalData; // Operation-specific details
}
```

### Error Types and Severities

**Error Types:**
- `ErrorType.syncManager`: Sync-related errors
- `ErrorType.database`: Core database operation errors

**Severity Levels:**
- `ErrorSeverity.info`: Low priority, informational
- `ErrorSeverity.warning`: Issues that don't affect functionality
- `ErrorSeverity.error`: Errors affecting functionality
- `ErrorSeverity.critical`: Critical errors that may crash the app

## Common Error Scenarios

### Sync Manager Errors

1. **Network Failures**: Temporary connectivity issues during sync
2. **Server Errors**: HTTP 500, authentication failures, etc.
3. **Permanent Failures**: HTTP 400 errors indicating bad data
4. **Retry Exhaustion**: All retry attempts failed
5. **Configuration Issues**: Invalid callback responses

Example logged operations:
- `sync_operation`: Overall sync process failures
- `batch_upload`: Batch upload failures
- `upload_permanent_failure`: Permanent failures (400 errors)
- `upload_final_failure`: Final failure after all retries
- `upload_retry_attempt`: Individual retry attempts

### Database Errors

1. **SQL Constraint Violations**: Foreign key, unique constraints
2. **Data Type Errors**: Invalid data for column types
3. **Migration Failures**: Schema migration issues
4. **Bulk Load Errors**: Large dataset import failures
5. **Connection Issues**: Database connection problems

Example logged operations:
- `insert`: Row insertion failures
- `update_by_primary_key`: Update operation failures
- `bulk_load`: Bulk data loading failures
- `migration`: Schema migration errors
- `query_execution`: General query failures

## Production Best Practices

### 1. Error Rate Monitoring

```dart
var errorCounts = <String, int>{};

ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
  // Track error rates
  final key = '${context.type.name}:${context.operation}';
  errorCounts[key] = (errorCounts[key] ?? 0) + 1;
  
  // Alert if error rate is too high
  if (errorCounts[key]! > 10) {
    AlertingService.sendAlert('High error rate for $key');
  }
  
  // Log to monitoring system
  LoggingService.error(error, context, stackTrace);
});
```

### 2. Error Correlation

```dart
ErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
  // Add correlation ID for tracking related errors
  final correlationId = generateCorrelationId();
  
  LoggingService.error(error, {
    ...context.additionalData,
    'correlation_id': correlationId,
    'user_session': getCurrentSessionId(),
    'operation_sequence': getOperationSequence(),
  });
});
```

### 3. Error Sampling

```dart
var errorSampleRate = 0.1; // Log 10% of errors

ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
  // Always log critical errors
  if (context.severity == ErrorSeverity.critical) {
    LoggingService.error(error, context, stackTrace);
    return;
  }
  
  // Sample other errors
  if (Random().nextDouble() < errorSampleRate) {
    LoggingService.error(error, context, stackTrace);
  }
});
```

## Testing Error Logging

### Unit Testing

```dart
test('should log database errors correctly', () {
  dynamic capturedError;
  ErrorContext? capturedContext;
  
  ErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
    capturedError = error;
    capturedContext = context;
  });
  
  // Trigger a database error
  try {
    await dataAccess.insert('users', {}); // Missing required fields
  } catch (e) {
    // Expected to throw
  }
  
  expect(capturedError, isNotNull);
  expect(capturedContext?.type, equals(ErrorType.database));
  expect(capturedContext?.operation, equals('insert'));
});
```

### Integration Testing

```dart
test('should integrate with mock logging service', () async {
  final mockLogger = MockLoggingService();
  
  ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
    mockLogger.logError(error, context, stackTrace);
  });
  
  // Perform operations that might fail
  await performSyncOperations();
  
  // Verify logging service was called appropriately
  verify(mockLogger.logError(any, any, any)).called(greaterThan(0));
});
```

## Migration from Other Libraries

### From Standard Exception Handling

**Before:**
```dart
try {
  await dataAccess.insert('users', userData);
} catch (e) {
  print('Insert failed: $e');
  // Manual error tracking
}
```

**After:**
```dart
// Error logging is automatic
await dataAccess.insert('users', userData);
// Errors are automatically logged with full context
```

### From Manual Sync Error Handling

**Before:**
```dart
final syncManager = ServerSyncManager(
  uploadCallback: (operations) async {
    try {
      return await uploadToServer(operations);
    } catch (e) {
      print('Sync failed: $e');
      MyLogger.error('Sync error', {'error': e.toString()});
      rethrow;
    }
  },
);
```

**After:**
```dart
// Configure error logging once
ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
  MyLogger.error('Sync error: ${context.operation}', {
    'error': error.toString(),
    'context': context.additionalData,
    'stack_trace': stackTrace?.toString(),
  });
});

// Sync manager automatically logs all errors with context
final syncManager = ServerSyncManager(
  uploadCallback: (operations) async {
    return await uploadToServer(operations);
  },
);
```

## Troubleshooting

### Common Issues

1. **Errors not being logged**: Check that `ErrorLogger.setEnabled(true)` is called
2. **Too many errors**: Implement sampling or filtering in your callback
3. **Performance impact**: Use async logging to avoid blocking operations
4. **Missing context**: Ensure you're using the latest version with full context support

### Debug Mode

```dart
// Enable detailed error logging for debugging
ErrorLoggerHelpers.configureConsoleLogging(includeStackTrace: true);

// Add debug information to all errors
ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
  print('=== SYNC ERROR DEBUG ===');
  print('Error: $error');
  print('Context: $context');
  print('Additional Data: ${context.additionalData}');
  if (stackTrace != null) {
    print('Stack Trace:\n$stackTrace');
  }
  print('========================');
});
```

This error logging system provides comprehensive visibility into both sync operations and database operations, making it much easier to support applications in production and debug issues when they occur.