import 'dart:async';
import 'package:meta/meta.dart';

/// Types of errors that can be logged
enum ErrorType {
  /// Sync manager related errors (upload failures, network issues, etc.)
  syncManager,
  /// Database core library errors (SQL execution, migration, etc.)
  database,
}

/// Severity level of the error
enum ErrorSeverity {
  /// Low priority informational errors
  info,
  /// Warnings that don't affect functionality
  warning,
  /// Errors that affect functionality but don't crash the app
  error,
  /// Critical errors that may crash the app
  critical,
}

/// Context information for an error
@immutable
class ErrorContext {
  const ErrorContext({
    required this.type,
    required this.severity,
    required this.operation,
    this.tableName,
    this.additionalData = const {},
  });

  /// The type of error (sync or database)
  final ErrorType type;
  
  /// Severity level of the error
  final ErrorSeverity severity;
  
  /// The operation that was being performed when the error occurred
  final String operation;
  
  /// Table name if applicable
  final String? tableName;
  
  /// Additional context data (e.g., user ID, operation details)
  final Map<String, dynamic> additionalData;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorContext &&
          type == other.type &&
          severity == other.severity &&
          operation == other.operation &&
          tableName == other.tableName &&
          additionalData.toString() == other.additionalData.toString();

  @override
  int get hashCode => Object.hash(
    type, severity, operation, tableName, additionalData.toString()
  );

  @override
  String toString() => 'ErrorContext($type/$severity: $operation${tableName != null ? ' on $tableName' : ''})';
}

/// Callback function type for error logging
/// 
/// [error] The error/exception that occurred
/// [context] Additional context about the error
/// [stackTrace] Stack trace if available
typedef ErrorLogCallback = void Function(
  dynamic error, 
  ErrorContext context, 
  StackTrace? stackTrace
);

/// Global error logging system for the declarative_sqlite library
/// 
/// This class provides hooks for developers to integrate with their preferred
/// error logging solutions like Sentry, Azure App Insights, Firebase Crashlytics, etc.
/// 
/// Usage:
/// ```dart
/// // Set up error logging with Sentry
/// ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
///   Sentry.captureException(error, stackTrace: stackTrace, withScope: (scope) {
///     scope.setTag('error_type', context.type.name);
///     scope.setTag('severity', context.severity.name);
///     scope.setTag('operation', context.operation);
///     if (context.tableName != null) {
///       scope.setTag('table_name', context.tableName!);
///     }
///     scope.setContext('additional_data', context.additionalData);
///   });
/// });
/// 
/// // Set up database error logging
/// ErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
///   // Log to Azure App Insights
///   appInsights.trackException(error, properties: {
///     'error_type': context.type.name,
///     'severity': context.severity.name,
///     'operation': context.operation,
///     'table_name': context.tableName ?? 'unknown',
///     ...context.additionalData,
///   });
/// });
/// ```
class ErrorLogger {
  static ErrorLogCallback? _syncManagerErrorCallback;
  static ErrorLogCallback? _databaseErrorCallback;
  static bool _isEnabled = true;

  /// Sets the callback for sync manager errors
  /// 
  /// This callback will be called whenever the ServerSyncManager encounters
  /// errors during sync operations, upload failures, network issues, etc.
  static void setSyncManagerErrorCallback(ErrorLogCallback? callback) {
    _syncManagerErrorCallback = callback;
  }

  /// Sets the callback for database core library errors
  /// 
  /// This callback will be called whenever the core database operations
  /// encounter errors during SQL execution, migrations, data access, etc.
  static void setDatabaseErrorCallback(ErrorLogCallback? callback) {
    _databaseErrorCallback = callback;
  }

  /// Enables or disables error logging globally
  /// 
  /// When disabled, no error callbacks will be invoked
  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Whether error logging is currently enabled
  static bool get isEnabled => _isEnabled;

  /// Logs a sync manager error
  /// 
  /// This should be called from ServerSyncManager when errors occur
  static void logSyncError(
    dynamic error, 
    String operation, {
    ErrorSeverity severity = ErrorSeverity.error,
    String? tableName,
    Map<String, dynamic> additionalData = const {},
    StackTrace? stackTrace,
  }) {
    if (!_isEnabled || _syncManagerErrorCallback == null) return;

    final context = ErrorContext(
      type: ErrorType.syncManager,
      severity: severity,
      operation: operation,
      tableName: tableName,
      additionalData: additionalData,
    );

    try {
      _syncManagerErrorCallback!(error, context, stackTrace);
    } catch (e) {
      // Prevent error logging from causing additional errors
      // In production, this could be logged to console or ignored
      print('Error in sync manager error callback: $e');
    }
  }

  /// Logs a database core library error
  /// 
  /// This should be called from DataAccess and other core components when errors occur
  static void logDatabaseError(
    dynamic error, 
    String operation, {
    ErrorSeverity severity = ErrorSeverity.error,
    String? tableName,
    Map<String, dynamic> additionalData = const {},
    StackTrace? stackTrace,
  }) {
    if (!_isEnabled || _databaseErrorCallback == null) return;

    final context = ErrorContext(
      type: ErrorType.database,
      severity: severity,
      operation: operation,
      tableName: tableName,
      additionalData: additionalData,
    );

    try {
      _databaseErrorCallback!(error, context, stackTrace);
    } catch (e) {
      // Prevent error logging from causing additional errors
      // In production, this could be logged to console or ignored
      print('Error in database error callback: $e');
    }
  }

  /// Clears all error callbacks
  /// 
  /// Useful for testing or when reconfiguring error logging
  static void clearCallbacks() {
    _syncManagerErrorCallback = null;
    _databaseErrorCallback = null;
  }

  /// Helper method to create error context for sync operations
  static ErrorContext syncContext(
    String operation, {
    ErrorSeverity severity = ErrorSeverity.error,
    String? tableName,
    Map<String, dynamic> additionalData = const {},
  }) {
    return ErrorContext(
      type: ErrorType.syncManager,
      severity: severity,
      operation: operation,
      tableName: tableName,
      additionalData: additionalData,
    );
  }

  /// Helper method to create error context for database operations
  static ErrorContext databaseContext(
    String operation, {
    ErrorSeverity severity = ErrorSeverity.error,
    String? tableName,
    Map<String, dynamic> additionalData = const {},
  }) {
    return ErrorContext(
      type: ErrorType.database,
      severity: severity,
      operation: operation,
      tableName: tableName,
      additionalData: additionalData,
    );
  }
}

/// Helper class with pre-configured error logging setups for popular services
class ErrorLoggerHelpers {
  /// Configure error logging for Sentry
  /// 
  /// Example usage:
  /// ```dart
  /// import 'package:sentry/sentry.dart';
  /// 
  /// ErrorLoggerHelpers.configureSentry((error, context, stackTrace) {
  ///   Sentry.captureException(error, stackTrace: stackTrace, withScope: (scope) {
  ///     scope.setTag('error_type', context.type.name);
  ///     scope.setTag('severity', context.severity.name);
  ///     scope.setTag('operation', context.operation);
  ///     if (context.tableName != null) {
  ///       scope.setTag('table_name', context.tableName!);
  ///     }
  ///     scope.setContext('additional_data', context.additionalData);
  ///   });
  /// });
  /// ```
  static void configureSentry(ErrorLogCallback sentryCallback) {
    ErrorLogger.setSyncManagerErrorCallback(sentryCallback);
    ErrorLogger.setDatabaseErrorCallback(sentryCallback);
  }

  /// Configure error logging for Azure Application Insights
  /// 
  /// Example usage:
  /// ```dart
  /// ErrorLoggerHelpers.configureAzureAppInsights((error, context, stackTrace) {
  ///   appInsights.trackException(error, properties: {
  ///     'error_type': context.type.name,
  ///     'severity': context.severity.name,
  ///     'operation': context.operation,
  ///     'table_name': context.tableName ?? 'unknown',
  ///     'stack_trace': stackTrace?.toString(),
  ///     ...context.additionalData,
  ///   });
  /// });
  /// ```
  static void configureAzureAppInsights(ErrorLogCallback appInsightsCallback) {
    ErrorLogger.setSyncManagerErrorCallback(appInsightsCallback);
    ErrorLogger.setDatabaseErrorCallback(appInsightsCallback);
  }

  /// Configure error logging for Firebase Crashlytics
  /// 
  /// Example usage:
  /// ```dart
  /// import 'package:firebase_crashlytics/firebase_crashlytics.dart';
  /// 
  /// ErrorLoggerHelpers.configureFirebaseCrashlytics((error, context, stackTrace) {
  ///   FirebaseCrashlytics.instance.recordError(
  ///     error,
  ///     stackTrace,
  ///     reason: '${context.type.name}: ${context.operation}',
  ///     information: [
  ///       'Severity: ${context.severity.name}',
  ///       'Operation: ${context.operation}',
  ///       if (context.tableName != null) 'Table: ${context.tableName}',
  ///       ...context.additionalData.entries.map((e) => '${e.key}: ${e.value}'),
  ///     ],
  ///   );
  /// });
  /// ```
  static void configureFirebaseCrashlytics(ErrorLogCallback crashlyticsCallback) {
    ErrorLogger.setSyncManagerErrorCallback(crashlyticsCallback);
    ErrorLogger.setDatabaseErrorCallback(crashlyticsCallback);
  }

  /// Configure basic console logging for debugging
  /// 
  /// This is useful for development and debugging
  static void configureConsoleLogging({bool includeStackTrace = true}) {
    final callback = (dynamic error, ErrorContext context, StackTrace? stackTrace) {
      final timestamp = DateTime.now().toIso8601String();
      print('[$timestamp] ${context.severity.name.toUpperCase()}: ${context.type.name} error in ${context.operation}');
      if (context.tableName != null) {
        print('  Table: ${context.tableName}');
      }
      print('  Error: $error');
      if (context.additionalData.isNotEmpty) {
        print('  Additional Data: ${context.additionalData}');
      }
      if (includeStackTrace && stackTrace != null) {
        print('  Stack Trace:');
        print(stackTrace.toString().split('\n').take(10).map((line) => '    $line').join('\n'));
      }
      print('');
    };

    ErrorLogger.setSyncManagerErrorCallback(callback);
    ErrorLogger.setDatabaseErrorCallback(callback);
  }
}