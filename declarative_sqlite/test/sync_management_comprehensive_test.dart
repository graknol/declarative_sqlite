import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Sync Management Tests', () {
    late DeclarativeDatabase db;
    late ServerSyncManager syncManager;
    late TaskScheduler scheduler;

    setUp(() async {
      final schema = SchemaBuilder()
        ..table('users', (table) {
          table.text('id').notNull('');
          table.text('name').notNull('');
          table.text('email').notNull('');
          table.key(['id']).primary();
        })
        ..table('posts', (table) {
          table.text('id').notNull('');
          table.text('title').notNull('');
          table.text('user_id').notNull('');
          table.key(['id']).primary();
        })
        ..build();
      
      db = await DeclarativeDatabase.openInMemory('test', schema: schema);
      scheduler = TaskScheduler.withConfig(TaskSchedulerConfig.resourceConstrained);
      await scheduler.initializeWithDatabase(db);
    });

    tearDown(() async {
      await scheduler.shutdown();
      await db.close();
    });

    test('simplified onFetch callback receives table timestamps', () async {
      final receivedTimestamps = <String, Hlc?>{};
      
      syncManager = ServerSyncManager(
        database: db,
        onFetch: (database, tableTimestamps) async {
          receivedTimestamps.addAll(tableTimestamps);
        },
        onSend: (operations) async => true,
      );

      // Set some server timestamps
      await syncManager.updateTableTimestamp('users', Hlc.now());
      await syncManager.updateTableTimestamp('posts', Hlc.now());

      // Trigger sync
      await syncManager.performSync();

      expect(receivedTimestamps.containsKey('users'), isTrue);
      expect(receivedTimestamps.containsKey('posts'), isTrue);
      expect(receivedTimestamps['users'], isA<Hlc>());
      expect(receivedTimestamps['posts'], isA<Hlc>());
    });

    test('server timestamps are stored persistently in database', () async {
      syncManager = ServerSyncManager(
        database: db,
        onFetch: (database, tableTimestamps) async {},
        onSend: (operations) async => true,
      );

      final testHlc = Hlc.now();
      await syncManager.updateTableTimestamp('users', testHlc);

      // Verify timestamp is stored in database
      final timestamps = await db.query((q) => q.from('sync_server_timestamps')
                                              .where(col('table_name').eq('users')));
      
      expect(timestamps.length, equals(1));
      expect(timestamps.first.getValue<String>('table_name'), equals('users'));
      expect(timestamps.first.getValue<String>('server_timestamp'), equals(testHlc.toString()));
    });

    test('table timestamps persist across app restarts', () async {
      syncManager = ServerSyncManager(
        database: db,
        onFetch: (database, tableTimestamps) async {},
        onSend: (operations) async => true,
      );

      final testHlc = Hlc.now();
      await syncManager.updateTableTimestamp('users', testHlc);

      // Create new sync manager instance (simulating app restart)
      final newSyncManager = ServerSyncManager(
        database: db,
        onFetch: (database, tableTimestamps) async {
          expect(tableTimestamps['users']?.toString(), equals(testHlc.toString()));
        },
        onSend: (operations) async => true,
      );

      await newSyncManager.performSync();
    });

    test('TaskScheduler integration for sync operations', () async {
      bool syncExecuted = false;
      
      syncManager = ServerSyncManager(
        database: db,
        onFetch: (database, tableTimestamps) async {
          syncExecuted = true;
        },
        onSend: (operations) async => true,
      );

      // Schedule sync operation with TaskScheduler
      DatabaseMaintenanceTasks.scheduleSyncOperation(
        syncManager: syncManager,
        interval: Duration(milliseconds: 100),
        scheduler: scheduler,
      );

      await Future.delayed(Duration(milliseconds: 200));
      
      expect(syncExecuted, isTrue);
    });

    test('onSend receives dirty operations correctly', () async {
      final receivedOperations = <DirtyRow>[];
      
      syncManager = ServerSyncManager(
        database: db,
        onFetch: (database, tableTimestamps) async {},
        onSend: (operations) async {
          receivedOperations.addAll(operations);
          return true;
        },
      );

      // Create some dirty data
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'email': 'john@example.com',
      });

      await syncManager.performSync();

      expect(receivedOperations.length, greaterThan(0));
      expect(receivedOperations.first.tableName, equals('users'));
      expect(receivedOperations.first.rowId, isNotNull);
    });

    test('bulkLoad with server timestamp updates tracking', () async {
      syncManager = ServerSyncManager(
        database: db,
        onFetch: (database, tableTimestamps) async {},
        onSend: (operations) async => true,
      );

      final serverHlc = Hlc.now();
      
      // Simulate receiving data from server with timestamp
      await db.bulkLoad('users', [
        {
          'system_id': 'sys1',
          'id': 'user1',
          'name': 'Server User',
          'email': 'server@example.com',
        }
      ]);

      // Update server timestamp for this batch
      await syncManager.updateTableTimestamp('users', serverHlc);

      // Verify timestamp was recorded
      final timestamps = await db.query((q) => q.from('sync_server_timestamps')
                                              .where(col('table_name').eq('users')));
      
      expect(timestamps.length, equals(1));
      expect(timestamps.first.getValue<String>('server_timestamp'), equals(serverHlc.toString()));
    });

    test('delta sync only requests newer records', () async {
      final lastKnownHlc = Hlc.now();
      Map<String, Hlc?>? requestedTimestamps;
      
      syncManager = ServerSyncManager(
        database: db,
        onFetch: (database, tableTimestamps) async {
          requestedTimestamps = tableTimestamps;
        },
        onSend: (operations) async => true,
      );

      // Set last known server timestamp
      await syncManager.updateTableTimestamp('users', lastKnownHlc);

      await syncManager.performSync();

      expect(requestedTimestamps, isNotNull);
      expect(requestedTimestamps!['users']?.toString(), equals(lastKnownHlc.toString()));
    });
  });
}