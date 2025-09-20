import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'test_helper.dart';

void main() {
  group('ServerSyncManagerWidget', () {
    late DeclarativeDatabase database;

    setUpAll(() async {
      database = await createTestDatabase(schema: createTestSchema());
    });

    tearDownAll(() async {
      await database.close();
    });

    setUp(() async {
      await clearTestDatabase(database);
    });

    testWidgets('initializes sync manager with provided database', (WidgetTester tester) async {
      bool fetchCalled = false;
      bool sendCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: ServerSyncManagerWidget(
            database: database,
            retryStrategy: null,
            fetchInterval: const Duration(seconds: 1),
            onFetch: (db, table, lastSynced) async {
              fetchCalled = true;
            },
            onSend: (operations) async {
              sendCalled = true;
              return true;
            },
            child: const Text('Sync Test'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Sync Test'), findsOneWidget);

      // Note: Testing actual sync calls would require mocking the ServerSyncManager
      // or waiting for the sync interval, which is complex in widget tests
    });

    testWidgets('uses database from DatabaseProvider when no database provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider(
            schema: (builder) {
              builder.table('users', (table) {
                table.guid('id').notNull();
                table.text('name').notNull();
                table.key(['id']).primary();
              });
            },
            databaseName: 'provider_test.db',
            child: ServerSyncManagerWidget(
              retryStrategy: null,
              fetchInterval: const Duration(minutes: 5),
              onFetch: (db, table, lastSynced) async {},
              onSend: (operations) async => true,
              child: const Text('Provider Sync Test'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Provider Sync Test'), findsOneWidget);
    });

    testWidgets('handles missing database gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ServerSyncManagerWidget(
            database: null,
            retryStrategy: null,
            fetchInterval: const Duration(minutes: 5),
            onFetch: (db, table, lastSynced) async {},
            onSend: (operations) async => true,
            child: const Text('No Database Test'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('No Database Test'), findsOneWidget);
      // Should not crash when no database is available
    });

    testWidgets('restarts sync manager when configuration changes', (WidgetTester tester) async {
      Duration currentInterval = const Duration(minutes: 5);

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      currentInterval = const Duration(minutes: 10);
                    });
                  },
                  child: const Text('Change Interval'),
                ),
                ServerSyncManagerWidget(
                  database: database,
                  retryStrategy: null,
                  fetchInterval: currentInterval,
                  onFetch: (db, table, lastSynced) async {},
                  onSend: (operations) async => true,
                  child: const Text('Config Test'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Config Test'), findsOneWidget);

      // Change configuration
      await tester.tap(find.text('Change Interval'));
      await tester.pumpAndSettle();

      // Should not crash and should continue working
      expect(find.text('Config Test'), findsOneWidget);
    });

    testWidgets('restarts sync manager when database changes', (WidgetTester tester) async {
      final database2 = await createTestDatabase(schema: createTestSchema());
      DeclarativeDatabase currentDatabase = database;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      currentDatabase = currentDatabase == database ? database2 : database;
                    });
                  },
                  child: const Text('Switch Database'),
                ),
                ServerSyncManagerWidget(
                  database: currentDatabase,
                  retryStrategy: null,
                  fetchInterval: const Duration(minutes: 5),
                  onFetch: (db, table, lastSynced) async {},
                  onSend: (operations) async => true,
                  child: const Text('Database Switch Test'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Database Switch Test'), findsOneWidget);

      // Switch database
      await tester.tap(find.text('Switch Database'));
      await tester.pumpAndSettle();

      // Should not crash and should continue working
      expect(find.text('Database Switch Test'), findsOneWidget);

      await database2.close();
    });

    testWidgets('restarts sync manager when onFetch changes', (WidgetTester tester) async {
      bool useFirstHandler = true;

      Future<void> firstHandler(DeclarativeDatabase db, String table, DateTime? lastSynced) async {}
      Future<void> secondHandler(DeclarativeDatabase db, String table, DateTime? lastSynced) async {}

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      useFirstHandler = !useFirstHandler;
                    });
                  },
                  child: const Text('Change Handler'),
                ),
                ServerSyncManagerWidget(
                  database: database,
                  retryStrategy: null,
                  fetchInterval: const Duration(minutes: 5),
                  onFetch: useFirstHandler ? firstHandler : secondHandler,
                  onSend: (operations) async => true,
                  child: const Text('Handler Test'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Handler Test'), findsOneWidget);

      // Change handler
      await tester.tap(find.text('Change Handler'));
      await tester.pumpAndSettle();

      // Should not crash and should continue working
      expect(find.text('Handler Test'), findsOneWidget);
    });

    testWidgets('restarts sync manager when onSend changes', (WidgetTester tester) async {
      bool useFirstHandler = true;

      Future<bool> firstHandler(List<DirtyRow> operations) async => true;
      Future<bool> secondHandler(List<DirtyRow> operations) async => false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      useFirstHandler = !useFirstHandler;
                    });
                  },
                  child: const Text('Change Send Handler'),
                ),
                ServerSyncManagerWidget(
                  database: database,
                  retryStrategy: null,
                  fetchInterval: const Duration(minutes: 5),
                  onFetch: (db, table, lastSynced) async {},
                  onSend: useFirstHandler ? firstHandler : secondHandler,
                  child: const Text('Send Handler Test'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Send Handler Test'), findsOneWidget);

      // Change handler
      await tester.tap(find.text('Change Send Handler'));
      await tester.pumpAndSettle();

      // Should not crash and should continue working
      expect(find.text('Send Handler Test'), findsOneWidget);
    });

    testWidgets('properly disposes sync manager on widget disposal', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ServerSyncManagerWidget(
            database: database,
            retryStrategy: null,
            fetchInterval: const Duration(minutes: 5),
            onFetch: (db, table, lastSynced) async {},
            onSend: (operations) async => true,
            child: const Text('Disposal Test'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Disposal Test'), findsOneWidget);

      // Remove the widget tree
      await tester.pumpWidget(const MaterialApp(home: Text('Empty')));
      await tester.pumpAndSettle();

      // Should not crash during disposal
      expect(find.text('Empty'), findsOneWidget);
    });

    testWidgets('handles sync manager initialization errors gracefully', (WidgetTester tester) async {
      // Create a database that might cause issues
      final problematicDatabase = await createTestDatabase(schema: createTestSchema());
      await problematicDatabase.close(); // Close it to make it unusable

      await tester.pumpWidget(
        MaterialApp(
          home: ServerSyncManagerWidget(
            database: problematicDatabase,
            retryStrategy: null,
            fetchInterval: const Duration(minutes: 5),
            onFetch: (db, table, lastSynced) async {},
            onSend: (operations) async => true,
            child: const Text('Error Handling Test'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should not crash even with a problematic database
      expect(find.text('Error Handling Test'), findsOneWidget);
    });

    testWidgets('supports custom retry strategy', (WidgetTester tester) async {
      const customRetryStrategy = 'custom_strategy';

      await tester.pumpWidget(
        MaterialApp(
          home: ServerSyncManagerWidget(
            database: database,
            retryStrategy: customRetryStrategy,
            fetchInterval: const Duration(minutes: 5),
            onFetch: (db, table, lastSynced) async {},
            onSend: (operations) async => true,
            child: const Text('Retry Strategy Test'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Retry Strategy Test'), findsOneWidget);
    });

    testWidgets('works with complex widget tree', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider(
            schema: (builder) {
              builder.table('users', (table) {
                table.guid('id').notNull();
                table.text('name').notNull();
                table.key(['id']).primary();
              });
            },
            databaseName: 'complex_test.db',
            child: ServerSyncManagerWidget(
              retryStrategy: null,
              fetchInterval: const Duration(minutes: 5),
              onFetch: (db, table, lastSynced) async {},
              onSend: (operations) async => true,
              child: Scaffold(
                appBar: AppBar(title: const Text('Complex App')),
                body: const Center(
                  child: Text('Complex Widget Tree'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Complex App'), findsOneWidget);
      expect(find.text('Complex Widget Tree'), findsOneWidget);
    });
  });
}