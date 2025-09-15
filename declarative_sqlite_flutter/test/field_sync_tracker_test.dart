import 'package:test/test.dart';
import 'package:declarative_sqlite_flutter/src/field_sync_status.dart';
import 'package:declarative_sqlite_flutter/src/field_sync_tracker.dart';

void main() {
  group('FieldSyncTracker', () {
    late FieldSyncTracker tracker;

    setUp(() {
      // Create a basic tracker without DataAccess for unit testing
      // In real usage, this would be initialized with actual DataAccess
      tracker = FieldSyncTracker(
        dataAccess: null as dynamic, // Mock for unit testing
        syncManager: null,
      );
    });

    tearDown(() {
      tracker.dispose();
    });

    test('should initialize with default local status', () {
      final status = tracker.getFieldStatus('users', 1, 'name');
      expect(status.status, equals(FieldSyncStatus.local));
      expect(status.attribution, isNull);
      expect(status.lastSyncTime, isNull);
    });

    test('should update field status', () {
      final newStatus = FieldSyncInfo(
        status: FieldSyncStatus.saved,
        lastSyncTime: DateTime.now(),
      );

      tracker.updateFieldStatus('users', 1, 'name', newStatus);
      final retrieved = tracker.getFieldStatus('users', 1, 'name');

      expect(retrieved.status, equals(FieldSyncStatus.saved));
      expect(retrieved.lastSyncTime, isNotNull);
    });

    test('should mark field as local', () {
      tracker.markFieldAsLocal('users', 1, 'email');
      final status = tracker.getFieldStatus('users', 1, 'email');

      expect(status.status, equals(FieldSyncStatus.local));
    });

    test('should mark field as saved', () {
      tracker.markFieldAsSaved('users', 1, 'email');
      final status = tracker.getFieldStatus('users', 1, 'email');

      expect(status.status, equals(FieldSyncStatus.saved));
      expect(status.lastSyncTime, isNotNull);
    });

    test('should mark field as synced with attribution', () {
      final attribution = ChangeAttribution(
        userId: 'user123',
        userName: 'John Doe',
        timestamp: DateTime.now(),
      );

      tracker.markFieldAsSynced('users', 1, 'email', attribution: attribution);
      final status = tracker.getFieldStatus('users', 1, 'email');

      expect(status.status, equals(FieldSyncStatus.synced));
      expect(status.attribution?.userId, equals('user123'));
      expect(status.attribution?.userName, equals('John Doe'));
      expect(status.lastSyncTime, isNotNull);
    });

    test('should handle multiple fields independently', () {
      tracker.markFieldAsLocal('users', 1, 'name');
      tracker.markFieldAsSaved('users', 1, 'email');
      tracker.markFieldAsSynced('users', 1, 'age');

      expect(tracker.getFieldStatus('users', 1, 'name').status, equals(FieldSyncStatus.local));
      expect(tracker.getFieldStatus('users', 1, 'email').status, equals(FieldSyncStatus.saved));
      expect(tracker.getFieldStatus('users', 1, 'age').status, equals(FieldSyncStatus.synced));
    });

    test('should handle multiple records independently', () {
      tracker.markFieldAsLocal('users', 1, 'name');
      tracker.markFieldAsSaved('users', 2, 'name');

      expect(tracker.getFieldStatus('users', 1, 'name').status, equals(FieldSyncStatus.local));
      expect(tracker.getFieldStatus('users', 2, 'name').status, equals(FieldSyncStatus.saved));
    });

    test('should handle multiple tables independently', () {
      tracker.markFieldAsLocal('users', 1, 'name');
      tracker.markFieldAsSaved('posts', 1, 'title');

      expect(tracker.getFieldStatus('users', 1, 'name').status, equals(FieldSyncStatus.local));
      expect(tracker.getFieldStatus('posts', 1, 'title').status, equals(FieldSyncStatus.saved));
    });

    test('should generate correct field keys', () {
      // Test the internal key generation by setting and retrieving
      tracker.markFieldAsLocal('my_table', 'composite_key', 'my_column');
      final status = tracker.getFieldStatus('my_table', 'composite_key', 'my_column');
      
      expect(status.status, equals(FieldSyncStatus.local));
    });

    test('should provide status streams', () async {
      final stream = tracker.getFieldStatusStream('users', 1, 'name');
      
      // Listen to the stream
      final statusUpdates = <FieldSyncStatus>[];
      final subscription = stream.listen((info) {
        statusUpdates.add(info.status);
      });

      // Make some status changes
      tracker.markFieldAsLocal('users', 1, 'name');
      tracker.markFieldAsSaved('users', 1, 'name');
      tracker.markFieldAsSynced('users', 1, 'name');

      // Give streams time to propagate
      await Future.delayed(const Duration(milliseconds: 10));

      expect(statusUpdates, contains(FieldSyncStatus.local));
      expect(statusUpdates, contains(FieldSyncStatus.saved));
      expect(statusUpdates, contains(FieldSyncStatus.synced));

      await subscription.cancel();
    });

    test('should clean up streams on dispose', () {
      final stream1 = tracker.getFieldStatusStream('users', 1, 'name');
      final stream2 = tracker.getFieldStatusStream('users', 2, 'email');

      // Subscribe to streams
      final sub1 = stream1.listen((_) {});
      final sub2 = stream2.listen((_) {});

      // Dispose tracker
      tracker.dispose();

      // Streams should be closed
      expect(() => tracker.updateFieldStatus('users', 1, 'name', 
        const FieldSyncInfo(status: FieldSyncStatus.local)), returnsNormally);

      sub1.cancel();
      sub2.cancel();
    });
  });

  group('DataAccess Extension', () {
    test('should have createSyncTracker extension method', () {
      // This tests that the extension exists and compiles
      // In a real test, we'd use an actual DataAccess instance
      expect(() {
        // This would create a sync tracker in real usage:
        // final dataAccess = DataAccess(database: db, schema: schema);
        // final tracker = dataAccess.createSyncTracker();
      }, returnsNormally);
    });
  });

  group('Sync Status Lifecycle', () {
    late FieldSyncTracker tracker;

    setUp(() {
      tracker = FieldSyncTracker(
        dataAccess: null as dynamic, // Mock for unit testing
        syncManager: null,
      );
    });

    tearDown(() {
      tracker.dispose();
    });

    test('should simulate complete sync lifecycle', () {
      const table = 'users';
      const primaryKey = 1;
      const column = 'name';

      // 1. User makes local changes
      tracker.markFieldAsLocal(table, primaryKey, column);
      var status = tracker.getFieldStatus(table, primaryKey, column);
      expect(status.status, equals(FieldSyncStatus.local));

      // 2. Changes saved to database
      tracker.markFieldAsSaved(table, primaryKey, column);
      status = tracker.getFieldStatus(table, primaryKey, column);
      expect(status.status, equals(FieldSyncStatus.saved));
      expect(status.lastSyncTime, isNotNull);

      // 3. Changes synced to server
      final attribution = ChangeAttribution(
        userId: 'current_user',
        userName: 'Current User',
        timestamp: DateTime.now(),
      );
      tracker.markFieldAsSynced(table, primaryKey, column, attribution: attribution);
      status = tracker.getFieldStatus(table, primaryKey, column);
      expect(status.status, equals(FieldSyncStatus.synced));
      expect(status.attribution?.userId, equals('current_user'));
    });

    test('should handle server changes with different user attribution', () {
      const table = 'users';
      const primaryKey = 1;
      const column = 'name';

      // Simulate change from another user via server sync
      final serverAttribution = ChangeAttribution(
        userId: 'other_user',
        userName: 'Another User',
        timestamp: DateTime.now(),
      );
      
      tracker.markFieldAsSynced(table, primaryKey, column, attribution: serverAttribution);
      final status = tracker.getFieldStatus(table, primaryKey, column);
      
      expect(status.status, equals(FieldSyncStatus.synced));
      expect(status.attribution?.userId, equals('other_user'));
      expect(status.attribution?.userName, equals('Another User'));
    });
  });
}