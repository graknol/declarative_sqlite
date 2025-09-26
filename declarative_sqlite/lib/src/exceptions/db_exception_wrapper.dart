import 'dart:async';
import 'dart:developer' as developer;
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
      final dbException = DbExceptionMapper.mapException(
        e,
        DbOperationType.create,
        tableName: tableName,
        columnName: columnName,
        context: context,
      );
      
      // Log constraint violations for developer debugging with severity-based levels
      if (dbException.errorCategory == DbErrorCategory.constraintViolation) {
        final constraintType = _getConstraintType(dbException.message);
        final logLevel = _getConstraintLogLevel(constraintType);
        final emoji = _getConstraintEmoji(constraintType);
        
        developer.log(
          '$emoji Constraint violation in CREATE: ${dbException.message}${tableName != null ? ' [table: $tableName]' : ''}${columnName != null ? ' [column: $columnName]' : ''} [type: $constraintType]',
          name: 'DbConstraint${constraintType.name}',
          level: logLevel,
          error: e,
        );
      }
      
      throw dbException;
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
      final dbException = DbExceptionMapper.mapException(
        e,
        DbOperationType.read,
        tableName: tableName,
        columnName: columnName,
        context: context,
      );
      
      // Log constraint violations for developer debugging with severity-based levels
      if (dbException.errorCategory == DbErrorCategory.constraintViolation) {
        final constraintType = _getConstraintType(dbException.message);
        final logLevel = _getConstraintLogLevel(constraintType);
        final emoji = _getConstraintEmoji(constraintType);
        
        developer.log(
          '$emoji Constraint violation in READ: ${dbException.message}${tableName != null ? ' [table: $tableName]' : ''}${columnName != null ? ' [column: $columnName]' : ''} [type: $constraintType]',
          name: 'DbConstraint${constraintType.name}',
          level: logLevel,
          error: e,
        );
      }
      
      throw dbException;
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
      final dbException = DbExceptionMapper.mapException(
        e,
        DbOperationType.update,
        tableName: tableName,
        columnName: columnName,
        context: context,
      );
      
      // Log constraint violations for developer debugging with severity-based levels
      if (dbException.errorCategory == DbErrorCategory.constraintViolation) {
        final constraintType = _getConstraintType(dbException.message);
        final logLevel = _getConstraintLogLevel(constraintType);
        final emoji = _getConstraintEmoji(constraintType);
        
        developer.log(
          '$emoji Constraint violation in UPDATE: ${dbException.message}${tableName != null ? ' [table: $tableName]' : ''}${columnName != null ? ' [column: $columnName]' : ''} [type: $constraintType]',
          name: 'DbConstraint${constraintType.name}',
          level: logLevel,
          error: e,
        );
      }
      
      throw dbException;
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
      final dbException = DbExceptionMapper.mapException(
        e,
        DbOperationType.delete,
        tableName: tableName,
        context: context,
      );
      
      // Log constraint violations for developer debugging with severity-based levels
      if (dbException.errorCategory == DbErrorCategory.constraintViolation) {
        final constraintType = _getConstraintType(dbException.message);
        final logLevel = _getConstraintLogLevel(constraintType);
        final emoji = _getConstraintEmoji(constraintType);
        
        developer.log(
          '$emoji Constraint violation in DELETE: ${dbException.message}${tableName != null ? ' [table: $tableName]' : ''} [type: $constraintType]',
          name: 'DbConstraint${constraintType.name}',
          level: logLevel,
          error: e,
        );
      }
      
      throw dbException;
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
      final dbException = DbExceptionMapper.mapException(
        e,
        DbOperationType.transaction,
        context: context,
      );
      
      // Log constraint violations for developer debugging with severity-based levels
      if (dbException.errorCategory == DbErrorCategory.constraintViolation) {
        final constraintType = _getConstraintType(dbException.message);
        final logLevel = _getConstraintLogLevel(constraintType);
        final emoji = _getConstraintEmoji(constraintType);
        
        developer.log(
          '$emoji Constraint violation in TRANSACTION: ${dbException.message} [type: $constraintType]',
          name: 'DbConstraint${constraintType.name}',
          level: logLevel,
          error: e,
        );
      }
      
      throw dbException;
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
      final dbException = DbExceptionMapper.mapException(
        e,
        DbOperationType.connection,
        context: context,
      );
      
      // Log constraint violations for developer debugging with severity-based levels
      if (dbException.errorCategory == DbErrorCategory.constraintViolation) {
        final constraintType = _getConstraintType(dbException.message);
        final logLevel = _getConstraintLogLevel(constraintType);
        final emoji = _getConstraintEmoji(constraintType);
        
        developer.log(
          '$emoji Constraint violation in CONNECTION: ${dbException.message} [type: $constraintType]',
          name: 'DbConstraint${constraintType.name}',
          level: logLevel,
          error: e,
        );
      }
      
      throw dbException;
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
  
  /// Determines the constraint type from the error message
  static ConstraintType _getConstraintType(String message) {
    final lowerMessage = message.toLowerCase();
    
    if (lowerMessage.contains('unique')) {
      return ConstraintType.unique;
    } else if (lowerMessage.contains('not null')) {
      return ConstraintType.notNull;
    } else if (lowerMessage.contains('check')) {
      return ConstraintType.check;
    } else if (lowerMessage.contains('primary key') || lowerMessage.contains('pkey')) {
      return ConstraintType.primaryKey;
    } else {
      return ConstraintType.other;
    }
  }
  
  /// Gets the appropriate log level based on constraint type
  static int _getConstraintLogLevel(ConstraintType type) {
    switch (type) {
      case ConstraintType.primaryKey:
        return 1000; // SEVERE - Data integrity violations
      case ConstraintType.unique:
      case ConstraintType.notNull:
        return 900; // WARNING - Business logic violations
      case ConstraintType.check:
      case ConstraintType.other:
        return 800; // INFO - General constraint violations
    }
  }
  
  /// Gets an appropriate emoji based on constraint type for visual identification
  static String _getConstraintEmoji(ConstraintType type) {
    switch (type) {
      case ConstraintType.primaryKey:
        return '🔑'; // Key for primary key
      case ConstraintType.unique:
        return '⭐'; // Star for uniqueness
      case ConstraintType.notNull:
        return '❗'; // Exclamation for required fields
      case ConstraintType.check:
        return '✓'; // Check mark for check constraints
      case ConstraintType.other:
        return '⚠️'; // Warning for other constraints
    }
  }
}

/// Enum for different constraint violation types
enum ConstraintType {
  unique,
  notNull,
  check,
  primaryKey,
  other,
}

/// Extension to get readable names for constraint types
extension ConstraintTypeName on ConstraintType {
  String get name {
    switch (this) {
      case ConstraintType.unique:
        return 'Unique';
      case ConstraintType.notNull:
        return 'NotNull';
      case ConstraintType.check:
        return 'Check';
      case ConstraintType.primaryKey:
        return 'PrimaryKey';
      case ConstraintType.other:
        return 'Other';
    }
  }
}