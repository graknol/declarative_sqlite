import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'dart:async';

void main() {
  // Initialize sqflite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  group('ServerSyncManager Tests', () {
    late Database database;
    late SchemaBuilder schema;
    late DataAccess dataAccess;

    setUpAll(() async {
      database = await databaseFactory.openDatabase(':memory:');
      
      schema = SchemaBuilder()
        .table('tasks', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .integer('hours', (col) => col.lww())
          .real('rate', (col) => col.lww())
          .text('notes', (col) => col.lww())
          .text('status', (col) => col.notNull().withDefaultValue('pending')));

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
      
      dataAccess = await DataAccess.create(database: database, schema: schema, enableLWW: true);
    });

    tearDownAll(() async {
      await database.close();
    });

    setUp(() {
      // Clear operations before each test
      dataAccess.clearSyncedOperations();
    });

    test('can create ServerSyncManager with callback', () {
      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          return true; // Always succeed
        },
      );

      expect(syncManager.isAutoSyncEnabled, isFalse);
      expect(syncManager.isSyncInProgress, isFalse);
      
      syncManager.dispose();
    });

    test('syncs pending operations successfully', () async {
      // Create some pending operations
      await dataAccess.insert('tasks', {
        'title': 'Test Task 1',
        'hours': 10,
        'rate': 25.0,
        'notes': 'Initial notes',
      });
      
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 15);
      await dataAccess.updateLWWColumn('tasks', 1, 'notes', 'Updated notes');

      // Verify we have pending operations
      expect(dataAccess.getPendingOperations().length, equals(2));

      // Create sync manager with successful upload callback
      final uploadedOperations = <PendingOperation>[];
      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          uploadedOperations.addAll(operations);
          return true; // Success
        },
      );

      // Perform sync
      final result = await syncManager.syncNow();

      expect(result.success, isTrue);
      expect(result.syncedOperations.length, equals(2));
      expect(result.failedOperations.length, equals(0));
      expect(result.error, isNull);
      expect(uploadedOperations.length, equals(2));

      // Verify operations were marked as synced
      expect(dataAccess.getPendingOperations().length, equals(0));

      syncManager.dispose();
    });

    test('handles upload failures with retry logic', () async {
      // Create a pending operation
      await dataAccess.insert('tasks', {
        'title': 'Test Task 2',
        'hours': 8,
      });
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 12);

      var attemptCount = 0;
      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          attemptCount++;
          if (attemptCount < 3) {
            return false; // Fail first 2 attempts
          }
          return true; // Succeed on 3rd attempt
        },
        options: ServerSyncOptions(
          retryAttempts: 3,
          retryDelay: Duration(milliseconds: 10), // Fast for testing
        ),
      );

      final result = await syncManager.syncNow();

      expect(result.success, isTrue);
      expect(result.syncedOperations.length, equals(1));
      expect(attemptCount, equals(3)); // Should have retried

      syncManager.dispose();
    });

    test('handles permanent failures without infinite retry', () async {
      // Create a pending operation
      await dataAccess.insert('tasks', {
        'title': 'Test Task 3',
        'hours': 6,
      });
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 9);

      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          throw Exception('Unauthorized'); // Permanent error
        },
        options: ServerSyncOptions(
          retryAttempts: 2,
          retryDelay: Duration(milliseconds: 10),
        ),
      );

      final result = await syncManager.syncNow();

      expect(result.success, isFalse);
      expect(result.failedOperations.length, equals(1));
      expect(result.error, contains('Unauthorized'));

      // Operations should still be pending (not marked as synced)
      expect(dataAccess.getPendingOperations().length, equals(1));

      syncManager.dispose();
    });

    test('processes operations in batches', () async {
      // Create multiple pending operations
      for (int i = 0; i < 5; i++) {
        await dataAccess.insert('tasks', {
          'title': 'Task $i',
          'hours': 10 + i,
        });
        await dataAccess.updateLWWColumn('tasks', i + 1, 'hours', 15 + i);
      }

      final uploadBatches = <List<PendingOperation>>[];
      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          uploadBatches.add(List.from(operations));
          return true;
        },
        options: ServerSyncOptions(
          batchSize: 3, // Small batch size for testing
        ),
      );

      final result = await syncManager.syncNow();

      expect(result.success, isTrue);
      expect(result.syncedOperations.length, equals(5));
      expect(uploadBatches.length, equals(2)); // Should have 2 batches: 3 + 2
      expect(uploadBatches[0].length, equals(3));
      expect(uploadBatches[1].length, equals(2));

      syncManager.dispose();
    });

    test('handles auto-sync functionality', () async {
      // Create a pending operation
      await dataAccess.insert('tasks', {
        'title': 'Auto Sync Task',
        'hours': 4,
      });
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 7);

      var syncCount = 0;
      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          syncCount++;
          return true;
        },
        onSyncStatus: (result) {
          print('Sync completed: ${result.syncedOperations.length} operations synced');
        },
        options: ServerSyncOptions(
          syncInterval: Duration(milliseconds: 100), // Very frequent for testing
        ),
      );

      // Start auto-sync
      await syncManager.startAutoSync();
      expect(syncManager.isAutoSyncEnabled, isTrue);

      // Wait for at least one auto-sync
      await Future.delayed(Duration(milliseconds: 250));

      // Stop auto-sync
      syncManager.stopAutoSync();
      expect(syncManager.isAutoSyncEnabled, isFalse);

      expect(syncCount, greaterThanOrEqualTo(1));
      expect(dataAccess.getPendingOperations().length, equals(0));

      syncManager.dispose();
    });

    test('handles concurrent sync attempts correctly', () async {
      // Create pending operations
      await dataAccess.insert('tasks', {
        'title': 'Concurrent Test',
        'hours': 3,
      });
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 5);

      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          // Simulate slow upload
          await Future.delayed(Duration(milliseconds: 100));
          return true;
        },
      );

      // Try to start multiple sync operations concurrently
      final future1 = syncManager.syncNow();
      
      // This should throw because sync is already in progress
      expect(
        () => syncManager.syncNow(),
        throwsA(isA<StateError>()),
      );

      // Wait for first sync to complete
      final result = await future1;
      expect(result.success, isTrue);

      syncManager.dispose();
    });

    test('handles empty pending operations gracefully', () async {
      // Ensure no pending operations
      expect(dataAccess.getPendingOperations().length, equals(0));

      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          fail('Should not be called with empty operations');
        },
      );

      final result = await syncManager.syncNow();

      expect(result.success, isTrue);
      expect(result.syncedOperations.length, equals(0));
      expect(result.failedOperations.length, equals(0));

      syncManager.dispose();
    });

    test('provides sync status callbacks', () async {
      // Create pending operations
      await dataAccess.insert('tasks', {
        'title': 'Status Test',
        'hours': 2,
      });
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 4);

      SyncResult? receivedResult;
      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async => true,
        onSyncStatus: (result) {
          receivedResult = result;
        },
      );

      await syncManager.syncNow();

      expect(receivedResult, isNotNull);
      expect(receivedResult!.success, isTrue);
      expect(receivedResult!.syncedOperations.length, equals(1));

      syncManager.dispose();
    });

    test('handles exponential backoff correctly', () async {
      // Create a pending operation
      await dataAccess.insert('tasks', {
        'title': 'Backoff Test',
        'hours': 1,
      });
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 2);

      var attemptCount = 0;
      final attemptTimes = <DateTime>[];
      
      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          attemptCount++;
          attemptTimes.add(DateTime.now());
          if (attemptCount < 3) {
            return false; // Fail to trigger retry
          }
          return true;
        },
        options: ServerSyncOptions(
          retryAttempts: 3,
          retryDelay: Duration(milliseconds: 50), // Start with 50ms
          backoffMultiplier: 2.0,
        ),
      );

      final result = await syncManager.syncNow();

      expect(result.success, isTrue);
      expect(attemptCount, equals(3));
      expect(attemptTimes.length, equals(3));

      // Check that delays increased (with some tolerance for timing)
      if (attemptTimes.length >= 2) {
        final delay1 = attemptTimes[1].difference(attemptTimes[0]).inMilliseconds;
        expect(delay1, greaterThanOrEqualTo(45)); // At least ~50ms
      }

      syncManager.dispose();
    });
  });
}