import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/src/awareness_manager.dart';
import '../lib/src/awareness_indicator.dart';

void main() {
  group('AwarenessUser', () {
    test('should generate initials from name', () {
      expect(const AwarenessUser(name: 'John Smith').displayInitials, 'JS');
      expect(const AwarenessUser(name: 'John').displayInitials, 'J');
      expect(const AwarenessUser(name: '').displayInitials, '?');
      expect(const AwarenessUser(name: 'John Middle Smith').displayInitials, 'JM');
    });

    test('should use provided initials when available', () {
      expect(
        const AwarenessUser(name: 'John Smith', initials: 'JMS').displayInitials,
        'JMS',
      );
    });

    test('should generate consistent colors from names', () {
      final user1 = const AwarenessUser(name: 'John Smith');
      final user2 = const AwarenessUser(name: 'John Smith');
      final user3 = const AwarenessUser(name: 'Jane Doe');
      
      expect(user1.displayColor, user2.displayColor);
      expect(user1.displayColor, isNot(user3.displayColor));
    });

    test('should use provided color when available', () {
      const testColor = 0xFF123456;
      const user = AwarenessUser(name: 'John Smith', color: testColor);
      expect(user.displayColor, testColor);
    });
  });

  group('AwarenessContext', () {
    test('should generate correct context keys', () {
      expect(
        const AwarenessContext().contextKey,
        'global',
      );
      
      expect(
        const AwarenessContext(tableName: 'users').contextKey,
        'table:users',
      );
      
      expect(
        const AwarenessContext(
          tableName: 'users',
          recordId: 123,
        ).contextKey,
        'table:users|record:123',
      );
      
      expect(
        const AwarenessContext(
          tableName: 'users',
          recordId: 123,
          route: '/users/123',
        ).contextKey,
        'table:users|record:123|route:/users/123',
      );
    });
  });

  group('AwarenessManager', () {
    late AwarenessManager manager;
    late List<String> mockUserNames;
    int callCount = 0;

    setUp(() {
      mockUserNames = ['John Smith', 'Jane Doe', 'Bob Johnson'];
      callCount = 0;
      
      manager = AwarenessManager(
        onFetchAwareness: (context) async {
          callCount++;
          await Future.delayed(const Duration(milliseconds: 10));
          return mockUserNames;
        },
        pollingInterval: const Duration(milliseconds: 100),
        enableDebugLogging: false,
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('should start and stop tracking contexts', () {
      const context = AwarenessContext(tableName: 'users', recordId: 123);
      
      expect(manager.getAwarenessUsers(context), isEmpty);
      
      manager.startTracking(context);
      expect(manager.getAwarenessUsers(context), isEmpty); // Initially empty
      
      manager.stopTracking(context);
    });

    test('should fetch awareness data for tracked contexts', () async {
      const context = AwarenessContext(tableName: 'users', recordId: 123);
      
      manager.startTracking(context);
      
      // Wait for initial fetch
      await Future.delayed(const Duration(milliseconds: 50));
      
      final users = manager.getAwarenessUsers(context);
      expect(users, hasLength(3));
      expect(users.map((u) => u.name), containsAll(mockUserNames));
      expect(callCount, greaterThan(0));
    });

    test('should handle multiple contexts independently', () async {
      const context1 = AwarenessContext(tableName: 'users', recordId: 123);
      const context2 = AwarenessContext(tableName: 'posts', recordId: 456);
      
      manager.startTracking(context1);
      manager.startTracking(context2);
      
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Both contexts should have awareness data
      expect(manager.getAwarenessUsers(context1), hasLength(3));
      expect(manager.getAwarenessUsers(context2), hasLength(3));
      expect(callCount, greaterThanOrEqualTo(2));
    });

    test('should provide streams of awareness updates', () async {
      const context = AwarenessContext(tableName: 'users', recordId: 123);
      
      final stream = manager.getAwarenessStream(context);
      final updates = <List<AwarenessUser>>[];
      
      final subscription = stream.listen(updates.add);
      
      manager.startTracking(context);
      
      await Future.delayed(const Duration(milliseconds: 50));
      
      expect(updates, isNotEmpty);
      expect(updates.last, hasLength(3));
      
      await subscription.cancel();
    });

    test('should handle fetch errors gracefully', () async {
      final errorManager = AwarenessManager(
        onFetchAwareness: (context) async {
          throw Exception('Network error');
        },
        enableDebugLogging: false,
      );
      
      const context = AwarenessContext(tableName: 'users', recordId: 123);
      
      errorManager.startTracking(context);
      
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Should continue working despite errors
      expect(errorManager.getAwarenessUsers(context), isEmpty);
      
      errorManager.dispose();
    });

    test('should refresh all active contexts', () async {
      const context1 = AwarenessContext(tableName: 'users', recordId: 123);
      const context2 = AwarenessContext(tableName: 'posts', recordId: 456);
      
      manager.startTracking(context1);
      manager.startTracking(context2);
      
      final initialCallCount = callCount;
      
      await manager.refresh();
      
      // Should have made additional calls for both contexts
      expect(callCount, greaterThan(initialCallCount));
    });
  });

  group('AwarenessIndicator Widget Tests', () {
    testWidgets('should render empty when no users', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AwarenessIndicator(users: []),
          ),
        ),
      );
      
      expect(find.byType(AwarenessIndicator), findsOneWidget);
      // The widget should be empty (SizedBox.shrink)
    });

    testWidgets('should render single user avatar', (tester) async {
      const users = [AwarenessUser(name: 'John Smith')];
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AwarenessIndicator(users: users),
          ),
        ),
      );
      
      expect(find.byType(AwarenessIndicator), findsOneWidget);
      expect(find.text('JS'), findsOneWidget);
    });

    testWidgets('should render multiple users with stacking', (tester) async {
      const users = [
        AwarenessUser(name: 'John Smith'),
        AwarenessUser(name: 'Jane Doe'),
        AwarenessUser(name: 'Bob Johnson'),
      ];
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AwarenessIndicator(users: users, maxVisible: 2),
          ),
        ),
      );
      
      expect(find.byType(AwarenessIndicator), findsOneWidget);
      expect(find.text('JS'), findsOneWidget);
      expect(find.text('JD'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget); // Extra count
    });

    testWidgets('should show tooltip on hover', (tester) async {
      const users = [
        AwarenessUser(name: 'John Smith'),
        AwarenessUser(name: 'Jane Doe'),
      ];
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AwarenessIndicator(users: users, showTooltip: true),
          ),
        ),
      );
      
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('CompactAwarenessIndicator should use smaller size', (tester) async {
      const users = [AwarenessUser(name: 'John Smith')];
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompactAwarenessIndicator(users: users),
          ),
        ),
      );
      
      expect(find.byType(CompactAwarenessIndicator), findsOneWidget);
      expect(find.byType(AwarenessIndicator), findsOneWidget);
    });

    testWidgets('HorizontalAwarenessIndicator should render in row layout', (tester) async {
      const users = [
        AwarenessUser(name: 'John Smith'),
        AwarenessUser(name: 'Jane Doe'),
      ];
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HorizontalAwarenessIndicator(users: users),
          ),
        ),
      );
      
      expect(find.byType(HorizontalAwarenessIndicator), findsOneWidget);
      expect(find.byType(Row), findsOneWidget);
      expect(find.text('JS'), findsOneWidget);
      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('AwarenessBadge should show count', (tester) async {
      const users = [
        AwarenessUser(name: 'John Smith'),
        AwarenessUser(name: 'Jane Doe'),
        AwarenessUser(name: 'Bob Johnson'),
      ];
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AwarenessBadge(users: users),
          ),
        ),
      );
      
      expect(find.byType(AwarenessBadge), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });
}