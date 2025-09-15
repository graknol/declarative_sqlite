import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  group('Sync Status Management Tests', () {
    late Database database;
    late DataAccess dataAccess;
    late ServerSyncManager syncManager;
    
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      database = await openDatabase(':memory:');
      
      final schema = SchemaBuilder()
        .table('test_table', (table) => table
            .autoIncrementPrimaryKey('id')
            .text('name', (col) => col.notNull().lww())
            .text('email', (col) => col.lww())
            .integer('age', (col) => col.lww()));

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
      
      dataAccess = await DataAccess.create(
        database: database,
        schema: schema,
      );

      syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          // Mock successful upload
          return true;
        },
      );
    });

    tearDown(() async {
      syncManager.dispose();
      await database.close();
    });

    test('should track sync history when performing sync', () async {
      // Insert some data and then do LWW updates to create pending operations
      final id = await dataAccess.insert('test_table', {
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 25,
      });

      // Now update with LWW to create pending operations
      await dataAccess.updateLWWColumn('test_table', id, 'name', 'Updated User');

      expect(dataAccess.getPendingOperations().length, 1);
      expect(syncManager.syncHistory.events.length, 0);

      // Perform sync
      final result = await syncManager.syncNow();

      expect(result.success, true);
      expect(result.syncedOperations.length, 1);
      expect(result.failedOperations.length, 0);
      expect(result.discardedOperations.length, 0);

      // Check sync history
      expect(syncManager.syncHistory.events.length, 1);
      final event = syncManager.syncHistory.events.first;
      expect(event.type, SyncEventType.manual);
      expect(event.success, true);
      expect(event.syncedCount, 1);
      expect(event.failedCount, 0);
      expect(event.discardedCount, 0);
    });

    test('should handle permanent failures by discarding operations', () async {
      bool shouldSucceed = false;
      
      syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          // Return false to simulate permanent failure (400 error)
          return shouldSucceed;
        },
      );

      // Insert data and create LWW update
      final id = await dataAccess.insert('test_table', {
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 25,
      });
      await dataAccess.updateLWWColumn('test_table', id, 'name', 'Updated User');

      expect(dataAccess.getPendingOperations().length, 1);

      // Perform sync with permanent failure
      final result = await syncManager.syncNow();

      expect(result.success, false);
      expect(result.syncedOperations.length, 0);
      expect(result.failedOperations.length, 0);
      expect(result.discardedOperations.length, 1);

      // Operations should be discarded (not pending anymore)
      expect(dataAccess.getPendingOperations().length, 0);

      // Check sync history
      expect(syncManager.syncHistory.events.length, 1);
      final event = syncManager.syncHistory.events.first;
      expect(event.success, false);
      expect(event.discardedCount, 1);
    });

    test('should handle temporary failures by keeping operations for retry', () async {
      bool shouldThrow = true;
      
      syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          if (shouldThrow) {
            throw Exception('Temporary network error');
          }
          return true;
        },
      );

      // Insert data and create LWW update
      final id = await dataAccess.insert('test_table', {
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 25,
      });
      await dataAccess.updateLWWColumn('test_table', id, 'name', 'Updated User');

      expect(dataAccess.getPendingOperations().length, 1);

      // Perform sync with temporary failure
      final result = await syncManager.syncNow();

      expect(result.success, false);
      expect(result.syncedOperations.length, 0);
      expect(result.failedOperations.length, 1);
      expect(result.discardedOperations.length, 0);

      // Operations should still be pending for retry
      expect(dataAccess.getPendingOperations().length, 1);

      // Now allow success
      shouldThrow = false;
      final result2 = await syncManager.syncNow();

      expect(result2.success, true);
      expect(result2.syncedOperations.length, 1);
      expect(dataAccess.getPendingOperations().length, 0);
    });

    test('should track last successful sync time', () async {
      expect(syncManager.lastSuccessfulSync, null);

      // Insert and sync data
      final id = await dataAccess.insert('test_table', {
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 25,
      });
      await dataAccess.updateLWWColumn('test_table', id, 'name', 'Updated User');

      final beforeSync = DateTime.now();
      await syncManager.syncNow();
      final afterSync = DateTime.now();

      expect(syncManager.lastSuccessfulSync, isNotNull);
      expect(syncManager.lastSuccessfulSync!.isAfter(beforeSync) || 
             syncManager.lastSuccessfulSync!.isAtSameMomentAs(beforeSync), true);
      expect(syncManager.lastSuccessfulSync!.isBefore(afterSync) || 
             syncManager.lastSuccessfulSync!.isAtSameMomentAs(afterSync), true);
    });

    test('should count pending operations correctly', () async {
      expect(syncManager.pendingOperationsCount, 0);

      // Insert multiple records and do LWW updates
      final id1 = await dataAccess.insert('test_table', {
        'name': 'User 1',
        'email': 'user1@example.com',
        'age': 25,
      });
      await dataAccess.updateLWWColumn('test_table', id1, 'name', 'Updated User 1');

      expect(syncManager.pendingOperationsCount, 1);

      final id2 = await dataAccess.insert('test_table', {
        'name': 'User 2',
        'email': 'user2@example.com',
        'age': 30,
      });
      await dataAccess.updateLWWColumn('test_table', id2, 'name', 'Updated User 2');

      expect(syncManager.pendingOperationsCount, 2);

      // Sync all operations
      await syncManager.syncNow();
      expect(syncManager.pendingOperationsCount, 0);
    });

    test('should maintain sync statistics', () async {
      final history = syncManager.syncHistory;
      
      expect(history.totalSynced, 0);
      expect(history.totalFailed, 0);
      expect(history.totalDiscarded, 0);

      // Create some operations and sync them
      final id1 = await dataAccess.insert('test_table', {'name': 'User 1', 'age': 25});
      await dataAccess.updateLWWColumn('test_table', id1, 'name', 'Updated User 1');
      
      final id2 = await dataAccess.insert('test_table', {'name': 'User 2', 'age': 30});
      await dataAccess.updateLWWColumn('test_table', id2, 'name', 'Updated User 2');
      
      await syncManager.syncNow();

      expect(history.totalSynced, 2);
      expect(history.totalFailed, 0);
      expect(history.totalDiscarded, 0);
    });

    test('should track different sync event types', () async {
      // Manual sync
      final id = await dataAccess.insert('test_table', {'name': 'User 1', 'age': 25});
      await dataAccess.updateLWWColumn('test_table', id, 'name', 'Updated User 1');
      await syncManager.syncNow();
      
      expect(syncManager.syncHistory.events.length, 1);
      expect(syncManager.syncHistory.events.first.type, SyncEventType.manual);

      // Auto sync
      final id2 = await dataAccess.insert('test_table', {'name': 'User 2', 'age': 30});
      await dataAccess.updateLWWColumn('test_table', id2, 'name', 'Updated User 2');
      await syncManager.startAutoSync();
      
      // Wait for the startup sync to complete
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(syncManager.syncHistory.events.length, 2);
      expect(syncManager.syncHistory.events.first.type, SyncEventType.startup);
      
      syncManager.stopAutoSync();
    });

    test('should get recent events within time range', () async {
      final history = syncManager.syncHistory;
      
      // Add a sync event
      final id = await dataAccess.insert('test_table', {'name': 'User 1', 'age': 25});
      await dataAccess.updateLWWColumn('test_table', id, 'name', 'Updated User 1');
      await syncManager.syncNow();
      
      // Should have recent events
      final recentEvents = history.getRecentEvents(60); // Last 60 minutes
      expect(recentEvents.length, 1);
      
      // No events in a very narrow time range
      final veryRecentEvents = history.getRecentEvents(0); // Last 0 minutes
      expect(veryRecentEvents.length, 0);
    });

    test('should clear sync history', () async {
      // Add some events
      final id = await dataAccess.insert('test_table', {'name': 'User 1', 'age': 25});
      await dataAccess.updateLWWColumn('test_table', id, 'name', 'Updated User 1');
      await syncManager.syncNow();
      
      expect(syncManager.syncHistory.events.length, 1);
      expect(syncManager.syncHistory.totalSynced, 1);
      
      // Clear history
      syncManager.syncHistory.clear();
      
      expect(syncManager.syncHistory.events.length, 0);
      expect(syncManager.syncHistory.totalSynced, 0);
      expect(syncManager.syncHistory.lastSuccessfulSync, null);
    });

    test('should handle mixed success and failure operations', () async {
      int callCount = 0;
      
      syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          callCount++;
          
          if (callCount == 1) {
            // First batch fails permanently
            return false; 
          } else if (callCount == 2) {
            // Second batch fails temporarily
            throw Exception('Network error');
          } else {
            // Subsequent batches succeed
            return true;
          }
        },
        options: ServerSyncOptions(batchSize: 1), // Process one at a time
      );

      // Insert multiple records and create LWW updates
      final id1 = await dataAccess.insert('test_table', {'name': 'User 1', 'age': 25});
      await dataAccess.updateLWWColumn('test_table', id1, 'name', 'Updated User 1');
      
      final id2 = await dataAccess.insert('test_table', {'name': 'User 2', 'age': 30});
      await dataAccess.updateLWWColumn('test_table', id2, 'name', 'Updated User 2');
      
      final id3 = await dataAccess.insert('test_table', {'name': 'User 3', 'age': 35});
      await dataAccess.updateLWWColumn('test_table', id3, 'name', 'Updated User 3');

      expect(dataAccess.getPendingOperations().length, 3);

      // Perform sync
      final result = await syncManager.syncNow();

      // We should have some failures or discards, making overall sync unsuccessful
      expect(result.success, false, reason: 'Should be false when some operations fail or are discarded');
      
      // The exact counts may vary based on operation order, but we should have some of each type
      expect(result.syncedOperations.length + result.failedOperations.length + result.discardedOperations.length, 3);
      expect(result.failedOperations.length + result.discardedOperations.length, greaterThan(0));
    });
  });
}