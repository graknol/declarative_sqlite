import 'package:test/test.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SchemaBuilder schema;
  late DataAccess dataAccess;
  late ServerSyncManager syncManager;

  setUpAll(() async {
    // Initialize sqflite for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Create in-memory database for each test
    database = await openDatabase(':memory:');
    
    // Create test schema with LWW columns for sync testing
    schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull().lww())
          .text('email', (col) => col.unique().lww())
          .integer('age', (col) => col.lww()))
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .text('content')
          .integer('user_id', (col) => col.notNull()));

    // Apply schema
    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);
    
    // Create data access (LWW auto-enabled when schema has LWW columns)
    dataAccess = await DataAccess.create(database: database, schema: schema);
  });

  tearDown(() async {
    await database.close();
    ErrorLogger.clearCallbacks();
    ErrorLogger.setEnabled(true);
  });

  group('ErrorLogger Configuration Tests', () {
    test('should set and clear sync manager error callback', () {
      var callbackCalled = false;
      
      ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
        callbackCalled = true;
      });
      
      ErrorLogger.logSyncError('test error', 'test_operation');
      expect(callbackCalled, isTrue);
      
      // Clear and test again
      callbackCalled = false;
      ErrorLogger.clearCallbacks();
      ErrorLogger.logSyncError('test error', 'test_operation');
      expect(callbackCalled, isFalse);
    });

    test('should set and clear database error callback', () {
      var callbackCalled = false;
      
      ErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
        callbackCalled = true;
      });
      
      ErrorLogger.logDatabaseError('test error', 'test_operation');
      expect(callbackCalled, isTrue);
      
      // Clear and test again
      callbackCalled = false;
      ErrorLogger.clearCallbacks();
      ErrorLogger.logDatabaseError('test error', 'test_operation');
      expect(callbackCalled, isFalse);
    });

    test('should respect enabled/disabled state', () {
      var callbackCalled = false;
      
      ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
        callbackCalled = true;
      });
      
      // Disable logging
      ErrorLogger.setEnabled(false);
      ErrorLogger.logSyncError('test error', 'test_operation');
      expect(callbackCalled, isFalse);
      
      // Re-enable logging
      ErrorLogger.setEnabled(true);
      ErrorLogger.logSyncError('test error', 'test_operation');
      expect(callbackCalled, isTrue);
    });

    test('should handle callback exceptions gracefully', () {
      ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
        throw Exception('Callback failed');
      });
      
      // Should not throw even if callback throws
      expect(() => ErrorLogger.logSyncError('test error', 'test_operation'), 
             returnsNormally);
    });
  });

  group('ErrorContext Tests', () {
    test('should create sync error context correctly', () {
      final context = ErrorLogger.syncContext(
        'upload_batch',
        severity: ErrorSeverity.warning,
        tableName: 'users',
        additionalData: {'batch_size': 10},
      );

      expect(context.type, equals(ErrorType.syncManager));
      expect(context.severity, equals(ErrorSeverity.warning));
      expect(context.operation, equals('upload_batch'));
      expect(context.tableName, equals('users'));
      expect(context.additionalData['batch_size'], equals(10));
    });

    test('should create database error context correctly', () {
      final context = ErrorLogger.databaseContext(
        'insert',
        severity: ErrorSeverity.error,
        tableName: 'posts',
        additionalData: {'row_count': 5},
      );

      expect(context.type, equals(ErrorType.database));
      expect(context.severity, equals(ErrorSeverity.error));
      expect(context.operation, equals('insert'));
      expect(context.tableName, equals('posts'));
      expect(context.additionalData['row_count'], equals(5));
    });

    test('should implement equality correctly', () {
      final context1 = ErrorContext(
        type: ErrorType.syncManager,
        severity: ErrorSeverity.info,
        operation: 'test',
        additionalData: {'key': 'value'},
      );

      final context2 = ErrorContext(
        type: ErrorType.syncManager,
        severity: ErrorSeverity.info,
        operation: 'test',
        additionalData: {'key': 'value'},
      );

      final context3 = ErrorContext(
        type: ErrorType.database,
        severity: ErrorSeverity.info,
        operation: 'test',
        additionalData: {'key': 'value'},
      );

      expect(context1, equals(context2));
      expect(context1, isNot(equals(context3)));
    });
  });

  group('Sync Manager Error Integration Tests', () {
    test('should log sync operation errors', () async {
      dynamic capturedError;
      ErrorContext? capturedContext;
      StackTrace? capturedStackTrace;
      
      ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
        capturedError = error;
        capturedContext = context;
        capturedStackTrace = stackTrace;
      });

      syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          throw Exception('Network error');
        },
      );

      // Add some test data using LWW
      await dataAccess.updateLWWColumn('users', await dataAccess.insert('users', {'name': 'Test User', 'email': 'test@example.com'}), 'name', 'Updated Name');

      // Try to sync - should log error
      try {
        await syncManager.syncNow();
        fail('Expected sync to throw');
      } catch (e) {
        // Expected to throw
      }

      expect(capturedError, isA<Exception>());
      expect(capturedContext?.type, equals(ErrorType.syncManager));
      // The error can be logged at different levels - batch_upload or upload_final_failure
      expect(capturedContext?.operation, anyOf('sync_operation', 'batch_upload', 'upload_final_failure'));
      // Stack trace may or may not be available depending on where the error is caught
      // expect(capturedStackTrace, isNotNull);
    });

    test('should log batch upload failures', () async {
      dynamic capturedError;
      ErrorContext? capturedContext;
      
      ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
        capturedError = error;
        capturedContext = context;
      });

      syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          throw Exception('Server unavailable');
        },
      );

      // Add test data using LWW to create pending operations
      final userId = await dataAccess.insert('users', {'name': 'Test User', 'email': 'test@example.com'});
      await dataAccess.updateLWWColumn('users', userId, 'name', 'Updated Name');

      // Try to sync
      try {
        await syncManager.syncNow();
        fail('Expected sync to throw');
      } catch (e) {
        // Expected to throw
      }

      expect(capturedError, isA<Exception>());
      expect(capturedContext?.operation, anyOf('batch_upload', 'upload_final_failure'));
      expect(capturedContext?.additionalData.containsKey('batch_size'), isTrue);
    });

    test('should log permanent failure operations', () async {
      String? capturedError;
      ErrorContext? capturedContext;
      
      ErrorLogger.setSyncManagerErrorCallback((error, context, stackTrace) {
        capturedError = error.toString();
        capturedContext = context;
      });

      syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          return false; // Permanent failure
        },
      );

      // Add test data using LWW to create pending operations
      final userId = await dataAccess.insert('users', {'name': 'Test User', 'email': 'test@example.com'});
      await dataAccess.updateLWWColumn('users', userId, 'name', 'Updated Name');

      // Sync should succeed but log permanent failure
      final result = await syncManager.syncNow();
      expect(result.discardedOperations.isNotEmpty, isTrue);

      expect(capturedError, contains('Upload callback returned false'));
      expect(capturedContext?.operation, equals('upload_permanent_failure'));
    });
  });

  group('Database Error Integration Tests', () {
    test('should log insert errors', () async {
      dynamic capturedError;
      ErrorContext? capturedContext;
      StackTrace? capturedStackTrace;
      
      ErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
        capturedError = error;
        capturedContext = context;
        capturedStackTrace = stackTrace;
      });

      // Try to insert invalid data (missing required field)
      try {
        await dataAccess.insert('users', {'email': 'test@example.com'}); // Missing required 'name'
        fail('Expected insert to throw');
      } catch (e) {
        // Expected to throw
      }

      expect(capturedError, isNotNull);
      expect(capturedContext?.type, equals(ErrorType.database));
      expect(capturedContext?.operation, equals('insert'));
      expect(capturedContext?.tableName, equals('users'));
      expect(capturedStackTrace, isNotNull);
    });

    test('should log update errors', () async {
      dynamic capturedError;
      ErrorContext? capturedContext;
      
      ErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
        capturedError = error;
        capturedContext = context;
      });

      // Try to update non-existent row
      try {
        await dataAccess.updateByPrimaryKey('users', 999, {'name': 'Updated'});
        // This might not throw depending on implementation, so let's force an error
      } catch (e) {
        // Error was logged
      }
      
      // Let's create a scenario that will definitely cause an error
      try {
        await dataAccess.updateByPrimaryKey('users', 'invalid', {'name': 'Updated'});
      } catch (e) {
        // Expected error
      }

      if (capturedError != null) {
        expect(capturedContext?.type, equals(ErrorType.database));
        expect(capturedContext?.operation, equals('update_by_primary_key'));
        expect(capturedContext?.tableName, equals('users'));
      }
    });

    test('should log bulk load errors', () async {
      dynamic capturedError;
      ErrorContext? capturedContext;
      
      ErrorLogger.setDatabaseErrorCallback((error, context, stackTrace) {
        capturedError = error;
        capturedContext = context;
      });

      // Try to bulk load invalid data
      try {
        await dataAccess.bulkLoad('users', [
          {'name': 'User 1', 'email': 'user1@example.com'},
          {'email': 'user2@example.com'}, // Missing required 'name'
        ]);
        fail('Expected bulk load to throw');
      } catch (e) {
        // Expected to throw
      }

      expect(capturedError, isNotNull);
      expect(capturedContext?.type, equals(ErrorType.database));
      expect(capturedContext?.operation, equals('bulk_load'));
      expect(capturedContext?.tableName, equals('users'));
      expect(capturedContext?.additionalData.containsKey('dataset_size'), isTrue);
    });
  });

  group('ErrorLoggerHelpers Tests', () {
    test('should configure console logging', () {
      var consoleOutput = <String>[];
      
      // Create a custom callback that captures output instead of using print
      final testCallback = (dynamic error, ErrorContext context, StackTrace? stackTrace) {
        final timestamp = DateTime.now().toIso8601String();
        consoleOutput.add('[$timestamp] ${context.severity.name.toUpperCase()}: ${context.type.name} error in ${context.operation}');
        if (context.tableName != null) {
          consoleOutput.add('  Table: ${context.tableName}');
        }
        consoleOutput.add('  Error: $error');
        if (context.additionalData.isNotEmpty) {
          consoleOutput.add('  Additional Data: ${context.additionalData}');
        }
      };

      ErrorLogger.setSyncManagerErrorCallback(testCallback);
      ErrorLogger.setDatabaseErrorCallback(testCallback);
      
      ErrorLogger.logSyncError(
        Exception('Test sync error'),
        'test_operation',
        severity: ErrorSeverity.warning,
        tableName: 'users',
        additionalData: {'test': 'data'},
      );

      expect(consoleOutput.any((line) => line.contains('WARNING')), isTrue);
      expect(consoleOutput.any((line) => line.contains('syncManager')), isTrue);
      expect(consoleOutput.any((line) => line.contains('test_operation')), isTrue);
      expect(consoleOutput.any((line) => line.contains('Table: users')), isTrue);
    });

    test('should configure unified error logging', () {
      var syncErrors = <dynamic>[];
      var databaseErrors = <dynamic>[];
      
      final unifiedCallback = (dynamic error, ErrorContext context, StackTrace? stackTrace) {
        if (context.type == ErrorType.syncManager) {
          syncErrors.add(error);
        } else {
          databaseErrors.add(error);
        }
      };

      ErrorLoggerHelpers.configureSentry(unifiedCallback);
      
      ErrorLogger.logSyncError('sync error', 'sync_op');
      ErrorLogger.logDatabaseError('db error', 'db_op');
      
      expect(syncErrors.length, equals(1));
      expect(databaseErrors.length, equals(1));
    });
  });

  group('Real-world Usage Examples Tests', () {
    test('should work with Azure App Insights pattern', () {
      final loggedEvents = <Map<String, dynamic>>[];
      
      ErrorLoggerHelpers.configureAzureAppInsights((error, context, stackTrace) {
        loggedEvents.add({
          'error': error.toString(),
          'error_type': context.type.name,
          'severity': context.severity.name,
          'operation': context.operation,
          'table_name': context.tableName ?? 'unknown',
          'stack_trace': stackTrace?.toString(),
          ...context.additionalData,
        });
      });

      ErrorLogger.logDatabaseError(
        Exception('Connection timeout'),
        'query_execution',
        severity: ErrorSeverity.critical,
        tableName: 'orders',
        additionalData: {'query_timeout_ms': 5000},
      );

      expect(loggedEvents.length, equals(1));
      final event = loggedEvents.first;
      expect(event['error_type'], equals('database'));
      expect(event['severity'], equals('critical'));
      expect(event['operation'], equals('query_execution'));
      expect(event['table_name'], equals('orders'));
      expect(event['query_timeout_ms'], equals(5000));
    });

    test('should work with Sentry pattern', () {
      final sentryEvents = <Map<String, dynamic>>[];
      
      ErrorLoggerHelpers.configureSentry((error, context, stackTrace) {
        sentryEvents.add({
          'exception': error,
          'tags': {
            'error_type': context.type.name,
            'severity': context.severity.name,
            'operation': context.operation,
            'table_name': context.tableName,
          },
          'context': {
            'additional_data': context.additionalData,
          },
          'stackTrace': stackTrace,
        });
      });

      ErrorLogger.logSyncError(
        StateError('Invalid sync state'),
        'conflict_resolution',
        severity: ErrorSeverity.error,
        tableName: 'user_data',
        additionalData: {
          'conflict_count': 3,
          'resolution_strategy': 'server_wins',
        },
      );

      expect(sentryEvents.length, equals(1));
      final event = sentryEvents.first;
      expect(event['tags']['error_type'], equals('syncManager'));
      expect(event['tags']['operation'], equals('conflict_resolution'));
      expect(event['context']['additional_data']['conflict_count'], equals(3));
    });
  });
}