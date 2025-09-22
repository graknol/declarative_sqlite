import 'dart:async';
import 'db_exceptions.dart';
import 'db_exception_mapper.dart';

/// Utility class for wrapping database operations with exception handling
/// 
/// Automatically catches platform-specific exceptions and converts them
/// to developer-friendly DbException types.
class DbExceptionWrapper {
  /// Wraps a database create operation with exception handling
  static Future<T> wrapCreate<T>(
    Future<T> Function() operation, {
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  }) async {
    try {
      return await operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        DbOperationType.create,
        tableName: tableName,
        columnName: columnName,
        context: context,
      );
    }
  }

  /// Wraps a database read operation with exception handling
  static Future<T> wrapRead<T>(
    Future<T> Function() operation, {
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  }) async {
    try {
      return await operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        DbOperationType.read,
        tableName: tableName,
        columnName: columnName,
        context: context,
      );
    }
  }

  /// Wraps a database update operation with exception handling
  static Future<T> wrapUpdate<T>(
    Future<T> Function() operation, {
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  }) async {
    try {
      return await operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        DbOperationType.update,
        tableName: tableName,
        columnName: columnName,
        context: context,
      );
    }
  }

  /// Wraps a database delete operation with exception handling
  static Future<T> wrapDelete<T>(
    Future<T> Function() operation, {
    String? tableName,
    Map<String, Object?>? context,
  }) async {
    try {
      return await operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        DbOperationType.delete,
        tableName: tableName,
        context: context,
      );
    }
  }

  /// Wraps a database transaction operation with exception handling
  static Future<T> wrapTransaction<T>(
    Future<T> Function() operation, {
    Map<String, Object?>? context,
  }) async {
    try {
      return await operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        DbOperationType.transaction,
        context: context,
      );
    }
  }

  /// Wraps a database connection operation with exception handling
  static Future<T> wrapConnection<T>(
    Future<T> Function() operation, {
    Map<String, Object?>? context,
  }) async {
    try {
      return await operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        DbOperationType.connection,
        context: context,
      );
    }
  }

  /// Wraps a database migration operation with exception handling
  static Future<T> wrapMigration<T>(
    Future<T> Function() operation, {
    Map<String, Object?>? context,
  }) async {
    try {
      return await operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        DbOperationType.migration,
        context: context,
      );
    }
  }

  /// Generic wrapper that can handle any operation type
  static Future<T> wrap<T>(
    Future<T> Function() operation,
    DbOperationType operationType, {
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  }) async {
    try {
      return await operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        operationType,
        tableName: tableName,
        columnName: columnName,
        context: context,
      );
    }
  }

  /// Synchronous wrapper for operations that don't return Future
  static T wrapSync<T>(
    T Function() operation,
    DbOperationType operationType, {
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  }) {
    try {
      return operation();
    } on DbException {
      // Re-throw already wrapped exceptions
      rethrow;
    } on Exception catch (e) {
      throw DbExceptionMapper.mapException(
        e,
        operationType,
        tableName: tableName,
        columnName: columnName,
        context: context,
      );
    }
  }
}