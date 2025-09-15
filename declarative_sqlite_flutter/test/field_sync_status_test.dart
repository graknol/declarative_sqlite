import 'package:test/test.dart';
import 'package:declarative_sqlite_flutter/src/field_sync_status.dart';

void main() {
  group('FieldSyncStatus', () {
    test('should have correct enum values', () {
      expect(FieldSyncStatus.values.length, equals(3));
      expect(FieldSyncStatus.values, contains(FieldSyncStatus.local));
      expect(FieldSyncStatus.values, contains(FieldSyncStatus.saved));
      expect(FieldSyncStatus.values, contains(FieldSyncStatus.synced));
    });
  });

  group('ChangeAttribution', () {
    test('should create attribution with required fields', () {
      final timestamp = DateTime.now();
      final attribution = ChangeAttribution(
        userId: 'user123',
        userName: 'John Doe',
        timestamp: timestamp,
      );

      expect(attribution.userId, equals('user123'));
      expect(attribution.userName, equals('John Doe'));
      expect(attribution.timestamp, equals(timestamp));
    });
  });

  group('FieldSyncInfo', () {
    test('should create sync info with default values', () {
      const syncInfo = FieldSyncInfo(status: FieldSyncStatus.local);
      
      expect(syncInfo.status, equals(FieldSyncStatus.local));
      expect(syncInfo.attribution, isNull);
      expect(syncInfo.lastSyncTime, isNull);
    });

    test('should create sync info with all fields', () {
      final timestamp = DateTime.now();
      final attribution = ChangeAttribution(
        userId: 'user123',
        userName: 'John Doe',
        timestamp: timestamp,
      );
      
      final syncInfo = FieldSyncInfo(
        status: FieldSyncStatus.synced,
        attribution: attribution,
        lastSyncTime: timestamp,
      );

      expect(syncInfo.status, equals(FieldSyncStatus.synced));
      expect(syncInfo.attribution, equals(attribution));
      expect(syncInfo.lastSyncTime, equals(timestamp));
    });

    test('should copy with updated status', () {
      const original = FieldSyncInfo(status: FieldSyncStatus.local);
      final updated = original.copyWith(status: FieldSyncStatus.saved);

      expect(original.status, equals(FieldSyncStatus.local));
      expect(updated.status, equals(FieldSyncStatus.saved));
      expect(updated.attribution, equals(original.attribution));
      expect(updated.lastSyncTime, equals(original.lastSyncTime));
    });

    test('should copy with updated attribution', () {
      final originalTime = DateTime.now();
      final attribution1 = ChangeAttribution(
        userId: 'user1',
        userName: 'User One',
        timestamp: originalTime,
      );
      final attribution2 = ChangeAttribution(
        userId: 'user2',
        userName: 'User Two',
        timestamp: originalTime,
      );

      final original = FieldSyncInfo(
        status: FieldSyncStatus.saved,
        attribution: attribution1,
      );
      final updated = original.copyWith(attribution: attribution2);

      expect(updated.attribution?.userId, equals('user2'));
      expect(updated.attribution?.userName, equals('User Two'));
      expect(updated.status, equals(original.status));
    });

    test('should copy with updated lastSyncTime', () {
      final time1 = DateTime.now();
      final time2 = time1.add(const Duration(minutes: 5));

      const original = FieldSyncInfo(status: FieldSyncStatus.saved);
      final updated = original.copyWith(lastSyncTime: time2);

      expect(updated.lastSyncTime, equals(time2));
      expect(updated.status, equals(original.status));
    });
  });

  group('Sync Status Progression', () {
    test('should progress through sync states correctly', () {
      // Start with local changes
      var syncInfo = const FieldSyncInfo(status: FieldSyncStatus.local);
      expect(syncInfo.status, equals(FieldSyncStatus.local));

      // Save to database
      syncInfo = syncInfo.copyWith(
        status: FieldSyncStatus.saved,
        lastSyncTime: DateTime.now(),
      );
      expect(syncInfo.status, equals(FieldSyncStatus.saved));
      expect(syncInfo.lastSyncTime, isNotNull);

      // Sync to server with attribution
      final serverAttribution = ChangeAttribution(
        userId: 'server_sync',
        userName: 'Auto Sync',
        timestamp: DateTime.now(),
      );
      syncInfo = syncInfo.copyWith(
        status: FieldSyncStatus.synced,
        attribution: serverAttribution,
      );
      expect(syncInfo.status, equals(FieldSyncStatus.synced));
      expect(syncInfo.attribution?.userId, equals('server_sync'));
    });

    test('should handle user attribution for server changes', () {
      final userAttribution = ChangeAttribution(
        userId: 'user456',
        userName: 'Jane Smith',
        timestamp: DateTime.now(),
      );

      final syncInfo = FieldSyncInfo(
        status: FieldSyncStatus.synced,
        attribution: userAttribution,
        lastSyncTime: DateTime.now(),
      );

      expect(syncInfo.status, equals(FieldSyncStatus.synced));
      expect(syncInfo.attribution?.userId, equals('user456'));
      expect(syncInfo.attribution?.userName, equals('Jane Smith'));
    });
  });
}