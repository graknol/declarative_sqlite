import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() {
  // Initialize sqflite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  group('LWW (Last-Writer-Wins) Functionality Tests', () {
    late Database database;
    late SchemaBuilder schema;
    late DataAccess dataAccess;

    setUpAll(() async {
      database = await databaseFactory.openDatabase(':memory:');
      
      schema = SchemaBuilder()
        .table('tasks', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .integer('hours', (col) => col.lww()) // Mark as LWW column
          .real('rate', (col) => col.lww()) // Mark as LWW column
          .text('notes', (col) => col.lww()) // Mark as LWW column
          .text('status', (col) => col.notNull().withDefaultValue('pending')));

      final migrator = SchemaMigrator();
      await migrator.migrate(database, schema);
      
      dataAccess = await DataAccess.create(database: database, schema: schema);
    });

    tearDownAll(() async {
      await database.close();
    });

    setUp(() {
      // Clear operations before each test to avoid interference
      dataAccess.clearSyncedOperations();
    });

    test('can create table with LWW columns', () async {
      // Insert a task
      final taskId = await dataAccess.insert('tasks', {
        'title': 'Test Task',
        'hours': 10,
        'rate': 25.50,
        'notes': 'Initial notes',
        'status': 'in_progress',
      });

      expect(taskId, greaterThan(0));

      // Verify the task was inserted
      final task = await dataAccess.getByPrimaryKey('tasks', taskId);
      expect(task, isNotNull);
      expect(task!['title'], equals('Test Task'));
      expect(task['hours'], equals(10));
      expect(task['rate'], equals(25.50));
      expect(task['notes'], equals('Initial notes'));
    });

    test('can update LWW columns with conflict resolution', () async {
      // Insert a task
      final taskId = await dataAccess.insert('tasks', {
        'title': 'Conflict Test Task',
        'hours': 10,
        'rate': 25.00,
        'notes': 'Original notes',
        'status': 'active',
      });

      // Get initial timestamp for comparison
      await Future.delayed(Duration(milliseconds: 1)); // Ensure different timestamp

      // Update hours (user edit)
      final newHours = await dataAccess.updateLWWColumn('tasks', taskId, 'hours', 15);
      expect(newHours, equals(15));

      // Verify the value is immediately available (from cache or DB)
      final effectiveHours = await dataAccess.getLWWColumnValue('tasks', taskId, 'hours');
      expect(effectiveHours, equals(15));

      // Get the complete row with LWW resolution
      final task = await dataAccess.getLWWRow('tasks', taskId);
      expect(task, isNotNull);
      expect(task!['hours'], equals(15));
      expect(task['rate'], equals(25.00)); // Unchanged
    });

    test('resolves conflicts using HLC timestamp (LWW)', () async {
      // Insert a task
      final taskId = await dataAccess.insert('tasks', {
        'title': 'Timestamp Test',
        'hours': 10,
        'rate': 30.00,
        'status': 'active',
      });

      // Wait to ensure different timestamp
      await Future.delayed(Duration(milliseconds: 2));

      // Simulate user update with current timestamp
      final userValue = await dataAccess.updateLWWColumn('tasks', taskId, 'hours', 20);
      expect(userValue, equals(20));

      // Wait again for different timestamp
      await Future.delayed(Duration(milliseconds: 2));

      // Simulate server update with newer timestamp (should win)
      final serverTimestamp = SystemColumnUtils.generateHLCTimestamp();
      final serverValue = await dataAccess.updateLWWColumn(
        'tasks', 
        taskId, 
        'hours', 
        25, 
        explicitTimestamp: serverTimestamp,
        isFromServer: true,
      );
      expect(serverValue, equals(25));

      // The effective value should be the server value (newer timestamp)
      final effectiveValue = await dataAccess.getLWWColumnValue('tasks', taskId, 'hours');
      expect(effectiveValue, equals(25));
    });

    test('handles server updates with conflict resolution', () async {
      // Insert a task
      final taskId = await dataAccess.insert('tasks', {
        'title': 'Server Update Test',
        'hours': 8,
        'rate': 40.00,
        'notes': 'Client notes',
        'status': 'active',
      });

      // Wait to ensure different timestamp
      await Future.delayed(Duration(milliseconds: 2));

      // Apply server update with newer timestamp
      final serverTimestamp = SystemColumnUtils.generateHLCTimestamp();
      final effectiveValues = await dataAccess.applyServerUpdate(
        'tasks',
        taskId,
        {
          'hours': 12,
          'rate': 45.00,
          'notes': 'Server updated notes',
        },
        serverTimestamp,
      );

      print('Effective values: $effectiveValues'); // Debug output
      expect(effectiveValues['hours'], equals(12));
      expect(effectiveValues['rate'], equals(45.00));
      expect(effectiveValues['notes'], equals('Server updated notes'));

      // Verify with full row
      final task = await dataAccess.getLWWRow('tasks', taskId);
      print('Full task: $task'); // Debug output
      expect(task!['hours'], equals(12));
      expect(task['rate'], equals(45.00));
      expect(task['notes'], equals('Server updated notes'));
    });

    test('tracks pending operations for sync', () async {
      // Insert a task
      final taskId = await dataAccess.insert('tasks', {
        'title': 'Pending Operations Test',
        'hours': 5,
        'rate': 35.00,
        'status': 'active',
      });

      // Make user updates (should create pending operations)
      await dataAccess.updateLWWColumn('tasks', taskId, 'hours', 8);
      await dataAccess.updateLWWColumn('tasks', taskId, 'rate', 40.00);

      // Check pending operations
      final pendingOps = dataAccess.getPendingOperations();
      expect(pendingOps, hasLength(2));
      expect(pendingOps.every((op) => !op.isSynced), isTrue);
      expect(pendingOps.every((op) => op.tableName == 'tasks'), isTrue);

      // Mark one as synced
      dataAccess.markOperationSynced(pendingOps.first.id);
      
      final pendingAfterSync = dataAccess.getPendingOperations();
      expect(pendingAfterSync, hasLength(1));

      // Clear synced operations
      dataAccess.clearSyncedOperations();
      
      // Should still have the unsynced operation
      final remainingPending = dataAccess.getPendingOperations();
      expect(remainingPending, hasLength(1));
    });

    test('throws error for non-LWW columns', () async {
      // Insert a task
      final taskId = await dataAccess.insert('tasks', {
        'title': 'Non-LWW Test',
        'hours': 10,
        'status': 'active',
      });

      // Try to update a non-LWW column with LWW method (should throw)
      expect(
        () => dataAccess.updateLWWColumn('tasks', taskId, 'title', 'New Title'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('handles missing row gracefully', () async {
      // Try to get LWW value for non-existent row
      final value = await dataAccess.getLWWColumnValue('tasks', 99999, 'hours');
      expect(value, isNull);

      // Try to get LWW row for non-existent row
      final row = await dataAccess.getLWWRow('tasks', 99999);
      expect(row, isNull);
    });
  });
}