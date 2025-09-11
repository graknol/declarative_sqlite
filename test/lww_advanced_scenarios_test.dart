import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  // Initialize sqflite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  group('LWW Advanced Scenarios - Real-World Use Cases', () {
    late Database database;
    late SchemaBuilder schema;
    late LWWDataAccess dataAccess;

    setUpAll(() async {
      database = await databaseFactory.openDatabase(':memory:');
      
      // Schema matching the problem statement: job tasks with hours tracking
      schema = SchemaBuilder()
        .table('job_tasks', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('job_id', (col) => col.notNull())
          .text('task_name', (col) => col.notNull())
          .integer('hours_used', (col) => col.lww()) // LWW field for user edits
          .real('hourly_rate', (col) => col.lww()) // LWW field 
          .text('notes', (col) => col.lww()) // LWW field
          .text('status', (col) => col.notNull().withDefaultValue('active'))
          .date('last_updated') // Regular field, not LWW
          .index('idx_job_id', ['job_id']));

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
      
      dataAccess = await LWWDataAccess.create(database: database, schema: schema);
    });

    tearDownAll(() async {
      await database.close();
    });

    setUp(() {
      // Clear operations before each test
      dataAccess.clearAllPendingOperations();
    });

    test('scenario: user modifies quantity while offline, app closes, reopens, syncs later', () async {
      // Initial task creation (simulating server data)
      final taskId = await dataAccess.insert('job_tasks', {
        'job_id': 'JOB-123',
        'task_name': 'Database Development',
        'hours_used': 10,
        'hourly_rate': 75.0,
        'notes': 'Initial scope definition',
        'status': 'active',
        'last_updated': DateTime.now(),
      });

      print('📝 Initial task created with 10 hours');

      // User modifies hours_used while potentially offline
      await Future.delayed(Duration(milliseconds: 2));
      final userTimestamp = SystemColumnUtils.generateHLCTimestamp();
      final userHours = await dataAccess.updateLWWColumn(
        'job_tasks', taskId, 'hours_used', 15, 
        explicitTimestamp: userTimestamp,
      );
      expect(userHours, equals(15));
      print('👤 User updated hours to 15 (cache + pending operation created)');

      // Verify value is immediately available for UI (from cache)
      final immediateValue = await dataAccess.getLWWColumnValue('job_tasks', taskId, 'hours_used');
      expect(immediateValue, equals(15));
      print('💻 UI shows immediate value: $immediateValue');

      // Verify pending operation was created for sync
      final pendingOps = dataAccess.getPendingOperations();
      expect(pendingOps, hasLength(1));
      expect(pendingOps.first.tableName, equals('job_tasks'));
      expect(pendingOps.first.columnUpdates['hours_used']!.value, equals(15));
      print('📤 Pending operation created for server sync');

      // Simulate app restart by creating new data access instance (cache cleared)
      final newDataAccess = await LWWDataAccess.create(database: database, schema: schema);
      
      // Without cache, should still get DB value
      final afterRestart = await newDataAccess.getLWWColumnValue('job_tasks', taskId, 'hours_used');
      expect(afterRestart, equals(15));
      print('🔄 After app restart, DB value still available: $afterRestart');

      // Later, server sends conflicting update with older timestamp
      // Make sure server timestamp is definitely older than user's
      final userTimestampInt = int.parse(userTimestamp);
      final olderServerTimestamp = (userTimestampInt - 1000).toString(); // 1ms older
      
      final serverUpdateResult = await newDataAccess.applyServerUpdate(
        'job_tasks',
        taskId,
        {'hours_used': 12}, // Conflicting value
        olderServerTimestamp, // Older timestamp
      );

      // User's value should win due to newer timestamp
      expect(serverUpdateResult['hours_used'], equals(15));
      print('⚔️  Server update with older timestamp rejected (LWW: 15 wins over 12)');

      // Now server sends update with newer timestamp
      await Future.delayed(Duration(milliseconds: 2));
      final newerServerTimestamp = SystemColumnUtils.generateHLCTimestamp();
      
      final newerServerResult = await newDataAccess.applyServerUpdate(
        'job_tasks',
        taskId,
        {'hours_used': 20}, // New server value
        newerServerTimestamp, // Newer timestamp
      );

      // Server's newer value should win
      expect(newerServerResult['hours_used'], equals(20));
      print('🏆 Server update with newer timestamp accepted (LWW: 20 wins over 15)');
    });

    test('scenario: multiple field updates with different timestamps', () async {
      // Create task
      final taskId = await dataAccess.insert('job_tasks', {
        'job_id': 'JOB-456',
        'task_name': 'Frontend Development', 
        'hours_used': 5,
        'hourly_rate': 80.0,
        'notes': 'React component work',
        'status': 'active',
      });

      print('📝 Task created: 5 hours at \$80/hr');

      // User makes multiple quick updates with explicit timestamps
      await Future.delayed(Duration(milliseconds: 1));
      final hoursTimestamp = SystemColumnUtils.generateHLCTimestamp();
      await dataAccess.updateLWWColumn('job_tasks', taskId, 'hours_used', 8, explicitTimestamp: hoursTimestamp);
      
      await Future.delayed(Duration(milliseconds: 1));
      final rateTimestamp = SystemColumnUtils.generateHLCTimestamp();
      await dataAccess.updateLWWColumn('job_tasks', taskId, 'hourly_rate', 85.0, explicitTimestamp: rateTimestamp);
      
      await Future.delayed(Duration(milliseconds: 1));  
      final notesTimestamp = SystemColumnUtils.generateHLCTimestamp();
      await dataAccess.updateLWWColumn('job_tasks', taskId, 'notes', 'Updated component architecture', explicitTimestamp: notesTimestamp);

      print('👤 User made 3 rapid updates');

      // Verify all values are available immediately
      final row = await dataAccess.getLWWRow('job_tasks', taskId);
      expect(row!['hours_used'], equals(8));
      expect(row['hourly_rate'], equals(85.0));
      expect(row['notes'], equals('Updated component architecture'));
      print('💻 UI shows all immediate updates');

      // Should have 3 pending operations
      final pendingOps = dataAccess.getPendingOperations();
      expect(pendingOps, hasLength(3));
      print('📤 3 pending operations for sync');

      // Server sends bulk update, but with mixed timestamps
      // Use older timestamp (before user's hours update)
      final olderTimestamp = (int.parse(hoursTimestamp) - 1000).toString();
      // Use newer timestamp (after user's notes update) 
      final newerTimestamp = (int.parse(notesTimestamp) + 1000).toString();

      // Apply server updates with mixed conflict scenarios
      await dataAccess.applyServerUpdate('job_tasks', taskId, {
        'hours_used': 6 // Server's older value, should be rejected
      }, olderTimestamp);

      await dataAccess.applyServerUpdate('job_tasks', taskId, {
        'hourly_rate': 90.0, // Server's newer value, should be accepted
        'notes': 'Server updated notes' // Server's newer value, should be accepted
      }, newerTimestamp);

      // Verify final state
      final finalRow = await dataAccess.getLWWRow('job_tasks', taskId);
      expect(finalRow!['hours_used'], equals(8)); // User's value won
      expect(finalRow['hourly_rate'], equals(90.0)); // Server's value won  
      expect(finalRow['notes'], equals('Server updated notes')); // Server's value won

      print('🏁 Final state - hours: ${finalRow['hours_used']}, rate: ${finalRow['hourly_rate']}');
      print('   notes: "${finalRow['notes']}"');
    });

    test('scenario: offline user edits with eventual server reconciliation', () async {
      // Simulate initial server state
      final taskId = await dataAccess.insert('job_tasks', {
        'job_id': 'JOB-789',
        'task_name': 'Testing & QA',
        'hours_used': 12,
        'hourly_rate': 65.0,
        'notes': 'Writing unit tests',
        'status': 'active',
      });

      print('📝 Initial server state: 12 hours at \$65/hr');

      // Simulate user going offline and making edits
      print('📱 User goes offline...');
      
      await Future.delayed(Duration(milliseconds: 1));
      await dataAccess.updateLWWColumn('job_tasks', taskId, 'hours_used', 15);
      print('   👤 User edits hours: 12 → 15 (stored in cache + pending)');
      
      await Future.delayed(Duration(milliseconds: 1));
      await dataAccess.updateLWWColumn('job_tasks', taskId, 'notes', 'Added integration tests');
      print('   👤 User edits notes (stored in cache + pending)');

      // User continues working offline with immediate UI feedback
      final offlineRow = await dataAccess.getLWWRow('job_tasks', taskId);
      expect(offlineRow!['hours_used'], equals(15));
      expect(offlineRow['notes'], equals('Added integration tests'));
      print('   💻 UI shows user\'s changes immediately');

      // Check pending operations for when user comes back online
      var pendingOps = dataAccess.getPendingOperations();
      expect(pendingOps, hasLength(2));
      print('   📤 2 operations pending sync');

      // User comes back online, server has made changes too
      print('🌐 User comes back online...');
      
      await Future.delayed(Duration(milliseconds: 2)); // Ensure newer timestamp
      final serverTimestamp = SystemColumnUtils.generateHLCTimestamp();
      
      // Server had updated the hourly rate while user was offline
      await dataAccess.applyServerUpdate('job_tasks', taskId, {
        'hourly_rate': 70.0, // Server increased rate
        'notes': 'Added performance tests' // Server also updated notes
      }, serverTimestamp);

      // Final state should have:
      // - User's hours_used (user's timestamp newer for this field)
      // - Server's hourly_rate (server updated this field with newer timestamp)  
      // - Server's notes (server's timestamp newer for this field)
      final finalRow = await dataAccess.getLWWRow('job_tasks', taskId);
      expect(finalRow!['hours_used'], equals(15)); // User's value  
      expect(finalRow['hourly_rate'], equals(70.0)); // Server's value
      expect(finalRow['notes'], equals('Added performance tests')); // Server's value

      print('🏁 Final reconciled state:');
      print('   hours_used: ${finalRow['hours_used']} (user won)');
      print('   hourly_rate: ${finalRow['hourly_rate']} (server won)');  
      print('   notes: "${finalRow['notes']}" (server won)');

      // After successful sync, operations can be marked as synced
      pendingOps = dataAccess.getPendingOperations();
      for (final op in pendingOps) {
        dataAccess.markOperationSynced(op.id);
      }
      
      dataAccess.clearSyncedOperations();
      final remainingOps = dataAccess.getPendingOperations();
      expect(remainingOps, hasLength(0));
      print('✅ All operations synced and cleared');
    });

    test('demonstrates automatic background conflict resolution transparency', () async {
      // This test shows how the developer doesn't need to do anything special
      // for UI updates - they just use the regular data access methods
      
      final taskId = await dataAccess.insert('job_tasks', {
        'job_id': 'JOB-AUTO',
        'task_name': 'Automatic Conflict Resolution Demo',
        'hours_used': 20,
        'hourly_rate': 100.0,
        'notes': 'Original notes',
        'status': 'active',
      });

      // Developer code: Just update the value - LWW handling is transparent
      await dataAccess.updateLWWColumn('job_tasks', taskId, 'hours_used', 25);
      
      // Developer code: Get value for UI - immediately available
      final currentHours = await dataAccess.getLWWColumnValue('job_tasks', taskId, 'hours_used');
      expect(currentHours, equals(25));
      
      // Developer code: Get full row for UI rendering
      var task = await dataAccess.getLWWRow('job_tasks', taskId);
      expect(task!['hours_used'], equals(25));
      
      print('✨ Developer just calls normal methods, LWW magic happens behind the scenes');
      
      // Simulate server update (developer would call this in sync handler)
      await Future.delayed(Duration(milliseconds: 2));
      await dataAccess.applyServerUpdate('job_tasks', taskId, {
        'hours_used': 30,
        'notes': 'Server updated notes'
      }, SystemColumnUtils.generateHLCTimestamp());
      
      // UI automatically gets the resolved values
      task = await dataAccess.getLWWRow('job_tasks', taskId);  
      expect(task!['hours_used'], equals(30)); // Server won with newer timestamp
      expect(task['notes'], equals('Server updated notes'));
      
      print('🎯 UI automatically shows resolved values without developer intervention');
      print('   Final hours: ${task['hours_used']} (server won)');
      print('   Final notes: "${task['notes']}" (server won)');
    });
  });
}