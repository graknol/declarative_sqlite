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
/// DSQLiteErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
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
/// DSQLiteErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
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
class DSQLiteErrorLogger {
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