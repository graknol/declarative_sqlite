import 'package:sqflite_common/sqlite_api.dart' as sqflite;
import 'db_exceptions.dart';

/// Utility class for mapping platform-specific database exceptions
/// to developer-friendly DbException types
class DbExceptionMapper {
  /// Maps a platform exception to a DbException based on operation type and error details
  static DbException mapException(
    Exception originalException,
    DbOperationType operationType, {
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  }) {
    final errorMessage = originalException.toString();
    final lowerErrorMessage = errorMessage.toLowerCase();

    // Extract table name from error message if not provided
    final inferredTableName = tableName ?? _extractTableNameFromError(errorMessage);

    // Determine error category based on the exception type and message
    final errorCategory = _categorizeError(originalException, lowerErrorMessage);

    // Create appropriate exception based on operation type
    switch (operationType) {
      case DbOperationType.create:
        return _createInsertException(
          errorCategory,
          originalException,
          inferredTableName,
          columnName,
          context,
        );

      case DbOperationType.read:
        return _createReadException(
          errorCategory,
          originalException,
          inferredTableName,
          columnName,
          context,
        );

      case DbOperationType.update:
        return _createUpdateException(
          errorCategory,
          originalException,
          inferredTableName,
          columnName,
          context,
        );

      case DbOperationType.delete:
        return _createDeleteException(
          errorCategory,
          originalException,
          inferredTableName,
          context,
        );

      case DbOperationType.transaction:
        return _createTransactionException(
          errorCategory,
          originalException,
          context,
        );

      case DbOperationType.connection:
        return _createConnectionException(
          errorCategory,
          originalException,
          context,
        );

      case DbOperationType.migration:
        return _createMigrationException(
          errorCategory,
          originalException,
          context,
        );
    }
  }

  /// Categorizes an error based on the exception type and message content
  static DbErrorCategory _categorizeError(Exception originalException, String lowerErrorMessage) {
    // Check for SQLite-specific error codes and messages
    if (originalException is sqflite.DatabaseException) {
      final sqliteException = originalException;
      
      // Check by error codes first (more reliable)
      if (sqliteException.toString().contains('SQLITE_CONSTRAINT')) {
        return DbErrorCategory.constraintViolation;
      }
      
      if (sqliteException.toString().contains('SQLITE_BUSY') ||
          sqliteException.toString().contains('SQLITE_LOCKED')) {
        return DbErrorCategory.databaseLocked;
      }
      
      if (sqliteException.toString().contains('SQLITE_CORRUPT')) {
        return DbErrorCategory.corruption;
      }
      
      if (sqliteException.toString().contains('SQLITE_NOTFOUND') ||
          sqliteException.toString().contains('no such table') ||
          sqliteException.toString().contains('no such column')) {
        return DbErrorCategory.notFound;
      }
    }

    // Fallback to message-based detection
    if (lowerErrorMessage.contains('constraint') ||
        lowerErrorMessage.contains('unique') ||
        lowerErrorMessage.contains('foreign key') ||
        lowerErrorMessage.contains('primary key') ||
        lowerErrorMessage.contains('check constraint')) {
      return DbErrorCategory.constraintViolation;
    }

    if (lowerErrorMessage.contains('not found') ||
        lowerErrorMessage.contains('no such table') ||
        lowerErrorMessage.contains('no such column') ||
        lowerErrorMessage.contains('does not exist')) {
      return DbErrorCategory.notFound;
    }

    if (lowerErrorMessage.contains('locked') ||
        lowerErrorMessage.contains('busy') ||
        lowerErrorMessage.contains('timeout')) {
      return DbErrorCategory.databaseLocked;
    }

    if (lowerErrorMessage.contains('corrupt') ||
        lowerErrorMessage.contains('malformed')) {
      return DbErrorCategory.corruption;
    }

    if (lowerErrorMessage.contains('permission') ||
        lowerErrorMessage.contains('access denied') ||
        lowerErrorMessage.contains('unauthorized')) {
      return DbErrorCategory.accessDenied;
    }

    if (lowerErrorMessage.contains('invalid') ||
        lowerErrorMessage.contains('syntax error') ||
        lowerErrorMessage.contains('datatype mismatch')) {
      return DbErrorCategory.invalidData;
    }

    if (lowerErrorMessage.contains('conflict') ||
        lowerErrorMessage.contains('concurrent') ||
        lowerErrorMessage.contains('version')) {
      return DbErrorCategory.concurrencyConflict;
    }

    if (lowerErrorMessage.contains('schema') ||
        lowerErrorMessage.contains('migration')) {
      return DbErrorCategory.schemaMismatch;
    }

    if (lowerErrorMessage.contains('connection') ||
        lowerErrorMessage.contains('network') ||
        lowerErrorMessage.contains('disconnected')) {
      return DbErrorCategory.connectionError;
    }

    return DbErrorCategory.unknown;
  }

  /// Extracts table name from error message if possible
  static String? _extractTableNameFromError(String errorMessage) {
    // Try to extract table name from common error patterns
    final patterns = [
      RegExp(r'table (?:"|`)?(\w+)(?:"|`)?', caseSensitive: false),
      RegExp(r'in table (?:"|`)?(\w+)(?:"|`)?', caseSensitive: false),
      RegExp(r'on table (?:"|`)?(\w+)(?:"|`)?', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(errorMessage);
      if (match != null) {
        return match.group(1);
      }
    }

    return null;
  }

  static DbCreateException _createInsertException(
    DbErrorCategory errorCategory,
    Exception originalException,
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  ) {
    switch (errorCategory) {
      case DbErrorCategory.constraintViolation:
        return DbCreateException.constraintViolation(
          message: _getConstraintViolationMessage(originalException, tableName, columnName),
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );

      case DbErrorCategory.invalidData:
        return DbCreateException.invalidData(
          message: _getInvalidDataMessage(originalException, tableName, columnName),
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );

      default:
        return DbCreateException(
          errorCategory: errorCategory,
          message: 'Failed to create record${tableName != null ? ' in table $tableName' : ''}',
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );
    }
  }

  static DbReadException _createReadException(
    DbErrorCategory errorCategory,
    Exception originalException,
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  ) {
    switch (errorCategory) {
      case DbErrorCategory.notFound:
        return DbReadException.notFound(
          message: 'Record or resource not found${tableName != null ? ' in table $tableName' : ''}',
          tableName: tableName,
          originalException: originalException,
          context: context,
        );

      case DbErrorCategory.accessDenied:
        return DbReadException.accessDenied(
          message: 'Access denied when reading${tableName != null ? ' from table $tableName' : ''}',
          tableName: tableName,
          originalException: originalException,
          context: context,
        );

      default:
        return DbReadException(
          errorCategory: errorCategory,
          message: 'Failed to read record${tableName != null ? ' from table $tableName' : ''}',
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );
    }
  }

  static DbUpdateException _createUpdateException(
    DbErrorCategory errorCategory,
    Exception originalException,
    String? tableName,
    String? columnName,
    Map<String, Object?>? context,
  ) {
    switch (errorCategory) {
      case DbErrorCategory.constraintViolation:
        return DbUpdateException.constraintViolation(
          message: _getConstraintViolationMessage(originalException, tableName, columnName),
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );

      case DbErrorCategory.concurrencyConflict:
        return DbUpdateException.concurrencyConflict(
          message: 'Concurrency conflict when updating${tableName != null ? ' table $tableName' : ''}',
          tableName: tableName,
          originalException: originalException,
          context: context,
        );

      case DbErrorCategory.notFound:
        return DbUpdateException.notFound(
          message: 'Record to update not found${tableName != null ? ' in table $tableName' : ''}',
          tableName: tableName,
          originalException: originalException,
          context: context,
        );

      default:
        return DbUpdateException(
          errorCategory: errorCategory,
          message: 'Failed to update record${tableName != null ? ' in table $tableName' : ''}',
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );
    }
  }

  static DbDeleteException _createDeleteException(
    DbErrorCategory errorCategory,
    Exception originalException,
    String? tableName,
    Map<String, Object?>? context,
  ) {
    switch (errorCategory) {
      case DbErrorCategory.constraintViolation:
        return DbDeleteException.constraintViolation(
          message: 'Cannot delete record due to foreign key constraint${tableName != null ? ' in table $tableName' : ''}',
          tableName: tableName,
          originalException: originalException,
          context: context,
        );

      case DbErrorCategory.notFound:
        return DbDeleteException.notFound(
          message: 'Record to delete not found${tableName != null ? ' in table $tableName' : ''}',
          tableName: tableName,
          originalException: originalException,
          context: context,
        );

      default:
        return DbDeleteException(
          errorCategory: errorCategory,
          message: 'Failed to delete record${tableName != null ? ' from table $tableName' : ''}',
          tableName: tableName,
          originalException: originalException,
          context: context,
        );
    }
  }

  static DbTransactionException _createTransactionException(
    DbErrorCategory errorCategory,
    Exception originalException,
    Map<String, Object?>? context,
  ) {
    switch (errorCategory) {
      case DbErrorCategory.databaseLocked:
        return DbTransactionException.databaseLocked(
          message: 'Database is locked and transaction cannot proceed',
          originalException: originalException,
          context: context,
        );

      default:
        return DbTransactionException.rollback(
          message: 'Transaction failed and was rolled back',
          originalException: originalException,
          context: context,
        );
    }
  }

  static DbConnectionException _createConnectionException(
    DbErrorCategory errorCategory,
    Exception originalException,
    Map<String, Object?>? context,
  ) {
    switch (errorCategory) {
      case DbErrorCategory.corruption:
        return DbConnectionException.corruption(
          message: 'Database file is corrupted and cannot be opened',
          originalException: originalException,
          context: context,
        );

      default:
        return DbConnectionException.connectionFailed(
          message: 'Failed to establish database connection',
          originalException: originalException,
          context: context,
        );
    }
  }

  static DbMigrationException _createMigrationException(
    DbErrorCategory errorCategory,
    Exception originalException,
    Map<String, Object?>? context,
  ) {
    return DbMigrationException.schemaMismatch(
      message: 'Database schema migration failed',
      originalException: originalException,
      context: context,
    );
  }

  static String _getConstraintViolationMessage(
    Exception originalException,
    String? tableName,
    String? columnName,
  ) {
    final errorMessage = originalException.toString().toLowerCase();
    
    if (errorMessage.contains('unique')) {
      return 'Unique constraint violation${columnName != null ? ' on column $columnName' : ''}${tableName != null ? ' in table $tableName' : ''}';
    }
    
    if (errorMessage.contains('foreign key')) {
      return 'Foreign key constraint violation${tableName != null ? ' in table $tableName' : ''}';
    }
    
    if (errorMessage.contains('primary key')) {
      return 'Primary key constraint violation${tableName != null ? ' in table $tableName' : ''}';
    }
    
    if (errorMessage.contains('check')) {
      return 'Check constraint violation${columnName != null ? ' on column $columnName' : ''}${tableName != null ? ' in table $tableName' : ''}';
    }
    
    return 'Constraint violation${tableName != null ? ' in table $tableName' : ''}';
  }

  static String _getInvalidDataMessage(
    Exception originalException,
    String? tableName,
    String? columnName,
  ) {
    final errorMessage = originalException.toString().toLowerCase();
    
    if (errorMessage.contains('datatype mismatch')) {
      return 'Data type mismatch${columnName != null ? ' for column $columnName' : ''}${tableName != null ? ' in table $tableName' : ''}';
    }
    
    if (errorMessage.contains('syntax error')) {
      return 'Invalid SQL syntax in query';
    }
    
    return 'Invalid data provided${tableName != null ? ' for table $tableName' : ''}';
  }
}