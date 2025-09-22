/// Enumeration of database operation types that can fail
enum DbOperationType {
  create,
  read,
  update,
  delete,
  transaction,
  migration,
  connection,
}

/// Enumeration of database error categories
enum DbErrorCategory {
  /// Constraint violation (unique, foreign key, check, etc.)
  constraintViolation,
  
  /// Resource not found (table, column, record, etc.)
  notFound,
  
  /// Invalid data or operation
  invalidData,
  
  /// Permission or access denied
  accessDenied,
  
  /// Database is locked or busy
  databaseLocked,
  
  /// Connection issues
  connectionError,
  
  /// Database corruption
  corruption,
  
  /// Schema mismatch or migration issues
  schemaMismatch,
  
  /// Concurrency conflict (optimistic locking, etc.)
  concurrencyConflict,
  
  /// Unknown or unexpected error
  unknown,
}

/// Base class for all database exceptions
/// 
/// Provides a developer-friendly interface similar to REST API status codes
/// for handling database operations failures.
abstract class DbException implements Exception {
  /// The operation that failed
  final DbOperationType operationType;
  
  /// The category of error
  final DbErrorCategory errorCategory;
  
  /// Human-readable error message
  final String message;
  
  /// Optional table name related to the error
  final String? tableName;
  
  /// Optional column name related to the error
  final String? columnName;
  
  /// The original platform-specific exception that caused this error
  final Exception? originalException;
  
  /// Additional context information
  final Map<String, Object?>? context;

  const DbException({
    required this.operationType,
    required this.errorCategory,
    required this.message,
    this.tableName,
    this.columnName,
    this.originalException,
    this.context,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('$runtimeType: $message');
    
    if (tableName != null) {
      buffer.write(' (table: $tableName');
      if (columnName != null) {
        buffer.write(', column: $columnName');
      }
      buffer.write(')');
    }
    
    if (originalException != null) {
      buffer.write(' [Original: ${originalException.runtimeType}]');
    }
    
    return buffer.toString();
  }
}

/// Exception thrown when a record cannot be created
class DbCreateException extends DbException {
  const DbCreateException({
    required DbErrorCategory errorCategory,
    required String message,
    String? tableName,
    String? columnName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) : super(
          operationType: DbOperationType.create,
          errorCategory: errorCategory,
          message: message,
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );

  /// Creates an exception for constraint violations during insert
  factory DbCreateException.constraintViolation({
    required String message,
    String? tableName,
    String? columnName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbCreateException(
        errorCategory: DbErrorCategory.constraintViolation,
        message: message,
        tableName: tableName,
        columnName: columnName,
        originalException: originalException,
        context: context,
      );

  /// Creates an exception for invalid data during insert
  factory DbCreateException.invalidData({
    required String message,
    String? tableName,
    String? columnName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbCreateException(
        errorCategory: DbErrorCategory.invalidData,
        message: message,
        tableName: tableName,
        columnName: columnName,
        originalException: originalException,
        context: context,
      );
}

/// Exception thrown when a record cannot be read/found
class DbReadException extends DbException {
  const DbReadException({
    required DbErrorCategory errorCategory,
    required String message,
    String? tableName,
    String? columnName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) : super(
          operationType: DbOperationType.read,
          errorCategory: errorCategory,
          message: message,
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );

  /// Creates an exception for when a record is not found
  factory DbReadException.notFound({
    required String message,
    String? tableName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbReadException(
        errorCategory: DbErrorCategory.notFound,
        message: message,
        tableName: tableName,
        originalException: originalException,
        context: context,
      );

  /// Creates an exception for access denied during read
  factory DbReadException.accessDenied({
    required String message,
    String? tableName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbReadException(
        errorCategory: DbErrorCategory.accessDenied,
        message: message,
        tableName: tableName,
        originalException: originalException,
        context: context,
      );
}

/// Exception thrown when a record cannot be updated
class DbUpdateException extends DbException {
  const DbUpdateException({
    required DbErrorCategory errorCategory,
    required String message,
    String? tableName,
    String? columnName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) : super(
          operationType: DbOperationType.update,
          errorCategory: errorCategory,
          message: message,
          tableName: tableName,
          columnName: columnName,
          originalException: originalException,
          context: context,
        );

  /// Creates an exception for constraint violations during update
  factory DbUpdateException.constraintViolation({
    required String message,
    String? tableName,
    String? columnName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbUpdateException(
        errorCategory: DbErrorCategory.constraintViolation,
        message: message,
        tableName: tableName,
        columnName: columnName,
        originalException: originalException,
        context: context,
      );

  /// Creates an exception for concurrency conflicts during update
  factory DbUpdateException.concurrencyConflict({
    required String message,
    String? tableName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbUpdateException(
        errorCategory: DbErrorCategory.concurrencyConflict,
        message: message,
        tableName: tableName,
        originalException: originalException,
        context: context,
      );

  /// Creates an exception for when the record to update is not found
  factory DbUpdateException.notFound({
    required String message,
    String? tableName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbUpdateException(
        errorCategory: DbErrorCategory.notFound,
        message: message,
        tableName: tableName,
        originalException: originalException,
        context: context,
      );
}

/// Exception thrown when a record cannot be deleted
class DbDeleteException extends DbException {
  const DbDeleteException({
    required DbErrorCategory errorCategory,
    required String message,
    String? tableName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) : super(
          operationType: DbOperationType.delete,
          errorCategory: errorCategory,
          message: message,
          tableName: tableName,
          originalException: originalException,
          context: context,
        );

  /// Creates an exception for constraint violations during delete
  factory DbDeleteException.constraintViolation({
    required String message,
    String? tableName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbDeleteException(
        errorCategory: DbErrorCategory.constraintViolation,
        message: message,
        tableName: tableName,
        originalException: originalException,
        context: context,
      );

  /// Creates an exception for when the record to delete is not found
  factory DbDeleteException.notFound({
    required String message,
    String? tableName,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbDeleteException(
        errorCategory: DbErrorCategory.notFound,
        message: message,
        tableName: tableName,
        originalException: originalException,
        context: context,
      );
}

/// Exception thrown when a transaction fails
class DbTransactionException extends DbException {
  const DbTransactionException({
    required DbErrorCategory errorCategory,
    required String message,
    Exception? originalException,
    Map<String, Object?>? context,
  }) : super(
          operationType: DbOperationType.transaction,
          errorCategory: errorCategory,
          message: message,
          originalException: originalException,
          context: context,
        );

  /// Creates an exception for when a transaction is rolled back
  factory DbTransactionException.rollback({
    required String message,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbTransactionException(
        errorCategory: DbErrorCategory.concurrencyConflict,
        message: message,
        originalException: originalException,
        context: context,
      );

  /// Creates an exception for when a database is locked during transaction
  factory DbTransactionException.databaseLocked({
    required String message,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbTransactionException(
        errorCategory: DbErrorCategory.databaseLocked,
        message: message,
        originalException: originalException,
        context: context,
      );
}

/// Exception thrown when database connection fails
class DbConnectionException extends DbException {
  const DbConnectionException({
    required DbErrorCategory errorCategory,
    required String message,
    Exception? originalException,
    Map<String, Object?>? context,
  }) : super(
          operationType: DbOperationType.connection,
          errorCategory: errorCategory,
          message: message,
          originalException: originalException,
          context: context,
        );

  /// Creates an exception for connection failures
  factory DbConnectionException.connectionFailed({
    required String message,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbConnectionException(
        errorCategory: DbErrorCategory.connectionError,
        message: message,
        originalException: originalException,
        context: context,
      );

  /// Creates an exception for database corruption
  factory DbConnectionException.corruption({
    required String message,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbConnectionException(
        errorCategory: DbErrorCategory.corruption,
        message: message,
        originalException: originalException,
        context: context,
      );
}

/// Exception thrown when database migration fails
class DbMigrationException extends DbException {
  const DbMigrationException({
    required DbErrorCategory errorCategory,
    required String message,
    Exception? originalException,
    Map<String, Object?>? context,
  }) : super(
          operationType: DbOperationType.migration,
          errorCategory: errorCategory,
          message: message,
          originalException: originalException,
          context: context,
        );

  /// Creates an exception for schema mismatch
  factory DbMigrationException.schemaMismatch({
    required String message,
    Exception? originalException,
    Map<String, Object?>? context,
  }) =>
      DbMigrationException(
        errorCategory: DbErrorCategory.schemaMismatch,
        message: message,
        originalException: originalException,
        context: context,
      );
}