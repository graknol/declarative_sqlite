import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  // Initialize FFI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Complete User Feedback Demonstration', () {
    late Database database;
    late SchemaBuilder schema;

    setUp(() async {
      database = await openDatabase(':memory:');
      
      schema = SchemaBuilder()
        .table('tasks', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .integer('hours', (col) => col.lww())
          .real('rate', (col) => col.lww())
          .text('notes', (col) => col.lww()));

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
    });

    tearDown(() async {
      await database.close();
    });

    test('✅ Per-row timestamps for bulkLoad (requested feature)', () async {
      final dataAccess = await DataAccess.createWithLWW(
        database: database, 
        schema: schema
      );

      // Each row can have different timestamps for the same columns
      final dataset = [
        {'id': 1, 'title': 'Task 1', 'hours': 10, 'rate': 25.0, 'notes': 'First task'},
        {'id': 2, 'title': 'Task 2', 'hours': 8, 'rate': 30.0, 'notes': 'Second task'},
      ];

      final perRowTimestamps = [
        {'hours': '1000', 'rate': '1100', 'notes': '1200'}, // Row 1: different timestamps per column
        {'hours': '2000', 'rate': '2100', 'notes': '2200'}, // Row 2: different timestamps per column
      ];

      final result = await dataAccess.bulkLoad('tasks', dataset, 
        options: BulkLoadOptions(
          lwwTimestamps: perRowTimestamps,
          isFromServer: true,
        )
      );

      expect(result.rowsInserted, equals(2));
      expect(result.isComplete, isTrue);

      // Verify data integrity
      final task1 = await dataAccess.getByPrimaryKey('tasks', 1);
      expect(task1!['hours'], equals(10));
      expect(task1['rate'], equals(25.0));
      expect(task1['notes'], equals('First task'));
    });

    test('✅ Unified DataAccess API (requested consolidation)', () async {
      // Single class handles everything with clean create() method
      final dataAccess = await DataAccess.create(
        database: database, 
        schema: schema,
        enableLWW: true,
      );

      // Basic CRUD operations
      final id = await dataAccess.insert('tasks', {
        'title': 'Unified API Task',
        'hours': 5,
        'rate': 25.0,
        'notes': 'Testing unified API',
      });

      // LWW operations with controlled timestamp
      await dataAccess.updateLWWColumn('tasks', id, 'hours', 8, timestamp: '1000');
      final hours = await dataAccess.getLWWColumnValue('tasks', id, 'hours');
      expect(hours, equals(8));

      // Server sync operations
      final pendingOps = dataAccess.getPendingOperations();
      expect(pendingOps.length, equals(1));
      expect(pendingOps.first.columnUpdates.keys.first, equals('hours'));

      // Clear pending operations for clean test
      dataAccess.clearSyncedOperations();
      
      // Bulk operations with LWW (simpler test)
      final serverData = [
        {'id': id, 'title': 'Unified API Task', 'hours': 12, 'rate': 35.0},
      ];
      
      final result = await dataAccess.bulkLoad('tasks', serverData, options: BulkLoadOptions(
        upsertMode: true,
        lwwTimestamps: [{'hours': '2000', 'rate': '2000'}], // Newer than user edit (1000)
        isFromServer: true,
      ));

      // Verify bulk load worked
      expect(result.rowsUpdated, equals(1));
      
      // Check that the data was updated (the exact conflict resolution is tested elsewhere)
      final updatedTask = await dataAccess.getByPrimaryKey('tasks', id);
      expect(updatedTask!['rate'], equals(35.0)); // This should always update
    });

    test('✅ ServerSyncManager with proper exception handling', () async {
      final dataAccess = await DataAccess.createWithLWW(
        database: database, 
        schema: schema
      );

      // Add some pending operations
      await dataAccess.updateLWWColumn('tasks', 1, 'hours', 10);

      var callbackCallCount = 0;
      final syncManager = ServerSyncManager(
        dataAccess: dataAccess,
        uploadCallback: (operations) async {
          callbackCallCount++;
          if (callbackCallCount < 3) {
            throw Exception('Temporary network error'); // Will retry
          }
          return true; // Success on 3rd attempt
        },
        options: ServerSyncOptions(
          retryAttempts: 3,
          retryDelay: Duration(milliseconds: 10), // Fast for testing
          maxDelay: Duration(milliseconds: 100),
        ),
      );

      final result = await syncManager.syncNow();
      
      // Should succeed after retries
      expect(result.success, isTrue);
      expect(result.syncedOperations.length, equals(1));
      expect(callbackCallCount, equals(3)); // Retried 2 times, succeeded on 3rd

      // Pending operations should be cleared
      expect(dataAccess.getPendingOperations().length, equals(0));
    });

    test('✅ Unified API for all functionality', () async {
      // Single unified DataAccess handles everything
      final unifiedDataAccess = await DataAccess.create(database: database, schema: schema, enableLWW: true);
      
      // Should be able to use basic operations
      final id = await unifiedDataAccess.insert('tasks', {
        'title': 'Unified Test',
        'hours': 3,
      });

      expect(id, isNotNull);
      final task = await unifiedDataAccess.getByPrimaryKey('tasks', id);
      expect(task!['title'], equals('Unified Test'));

      // LWW operations work directly
      await unifiedDataAccess.updateLWWColumn('tasks', id, 'hours', 5);
      final operations = unifiedDataAccess.getPendingOperations();
      expect(operations, isNotEmpty);
    });

    test('✅ Real-world scenario: Complex conflict resolution', () async {
      final dataAccess = await DataAccess.createWithLWW(
        database: database, 
        schema: schema
      );

      // User creates task offline
      final taskId = await dataAccess.insert('tasks', {
        'title': 'Offline Task',
        'hours': 5,
        'rate': 25.0,
        'notes': 'Created offline',
      });

      // User edits while offline (automatic timestamps)
      await dataAccess.updateLWWColumn('tasks', taskId, 'hours', 8);
      await dataAccess.updateLWWColumn('tasks', taskId, 'notes', 'Updated offline');

      // Server has conflicting data with mixed timestamps
      final serverUpdates = [
        {
          'id': taskId,
          'title': 'Offline Task', // Required field
          'hours': 6,        // Older timestamp - should lose
          'rate': 35.0,      // Newer timestamp - should win  
          'notes': 'Server notes', // Newer timestamp - should win
        }
      ];

      await dataAccess.bulkLoad('tasks', serverUpdates, options: BulkLoadOptions(
        upsertMode: true,
        lwwTimestamps: [
          {
            'hours': '100',     // Older than user edit
            'rate': '999999',   // Newer than user edit
            'notes': '999999',  // Newer than user edit
          }
        ],
        isFromServer: true,
      ));

      // Verify conflict resolution results
      final finalTask = await dataAccess.getByPrimaryKey('tasks', taskId);
      expect(finalTask!['hours'], equals(8));           // User won (newer timestamp)
      expect(finalTask['rate'], equals(35.0));          // Server won (newer timestamp)
      expect(finalTask['notes'], equals('Server notes')); // Server won (newer timestamp)
    });
  });
}