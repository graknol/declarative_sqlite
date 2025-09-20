import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'test_helper.dart';

void main() {
  group('QueryListView', () {
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

    testWidgets('renders loading state initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueryListView<TestUser>(
              database: database,
              query: (q) => q.from('users'),
              mapper: TestUser.fromMap,
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => Text('Error: $error'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('renders empty list when no data', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueryListView<TestUser>(
              database: database,
              query: (q) => q.from('users'),
              mapper: TestUser.fromMap,
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => Text('Error: $error'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Should not show loading anymore
      expect(find.text('Loading...'), findsNothing);
      // Should show empty ListView
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('renders list items when data is available', (WidgetTester tester) async {
      // Insert test data
      await database.insert('users', {
        'id': 'user1',
        'name': 'Alice',
        'email': 'alice@example.com',
        'age': 25,
      });
      await database.insert('users', {
        'id': 'user2',
        'name': 'Bob',
        'email': 'bob@example.com',
        'age': 30,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueryListView<TestUser>(
              database: database,
              query: (q) => q.from('users'),
              mapper: TestUser.fromMap,
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => Text('Error: $error'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('automatically updates when data changes', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueryListView<TestUser>(
              database: database,
              query: (q) => q.from('users'),
              mapper: TestUser.fromMap,
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => Text('Error: $error'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Initially no users
      expect(find.text('Alice'), findsNothing);

      // Insert a user
      await database.insert('users', {
        'id': 'user1',
        'name': 'Alice',
        'email': 'alice@example.com',
        'age': 25,
      });

      await tester.pumpAndSettle();
      await waitForAsync();

      // Should automatically show the new user
      expect(find.text('Alice'), findsOneWidget);

      // Delete the user
      await database.delete('users', where: 'id = ?', whereArgs: ['user1']);

      await tester.pumpAndSettle();
      await waitForAsync();

      // Should automatically hide the user
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('handles query changes', (WidgetTester tester) async {
      // Insert test data
      await database.insert('users', {
        'id': 'user1',
        'name': 'Alice',
        'email': 'alice@example.com',
        'age': 25,
      });
      await database.insert('users', {
        'id': 'user2',
        'name': 'Bob',
        'email': 'bob@example.com',
        'age': 30,
      });

      bool showOnlyAlice = true;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        showOnlyAlice = !showOnlyAlice;
                      });
                    },
                    child: const Text('Toggle Filter'),
                  ),
                  Expanded(
                    child: QueryListView<TestUser>(
                      database: database,
                      query: (q) => showOnlyAlice
                          ? q.from('users').where(col('name').eq('Alice'))
                          : q.from('users'),
                      mapper: TestUser.fromMap,
                      loadingBuilder: (context) => const Text('Loading...'),
                      errorBuilder: (context, error) => Text('Error: $error'),
                      itemBuilder: (context, user) => Text(user.name),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Initially should show only Alice
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);

      // Toggle filter
      await tester.tap(find.text('Toggle Filter'));
      await tester.pumpAndSettle();
      await waitForAsync();

      // Now should show both users
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('handles database changes', (WidgetTester tester) async {
      final database2 = await createTestDatabase(schema: createTestSchema());

      // Insert data in first database
      await database.insert('users', {
        'id': 'user1',
        'name': 'Alice',
        'email': 'alice@example.com',
        'age': 25,
      });

      // Insert different data in second database
      await database2.insert('users', {
        'id': 'user2',
        'name': 'Bob',
        'email': 'bob@example.com',
        'age': 30,
      });

      DeclarativeDatabase currentDatabase = database;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        currentDatabase = currentDatabase == database ? database2 : database;
                      });
                    },
                    child: const Text('Switch Database'),
                  ),
                  Expanded(
                    child: QueryListView<TestUser>(
                      database: currentDatabase,
                      query: (q) => q.from('users'),
                      mapper: TestUser.fromMap,
                      loadingBuilder: (context) => const Text('Loading...'),
                      errorBuilder: (context, error) => Text('Error: $error'),
                      itemBuilder: (context, user) => Text(user.name),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Initially should show Alice (from first database)
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);

      // Switch database
      await tester.tap(find.text('Switch Database'));
      await tester.pumpAndSettle();
      await waitForAsync();

      // Now should show Bob (from second database)
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsOneWidget);

      await database2.close();
    });

    testWidgets('shows loading when database is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueryListView<TestUser>(
              database: null,
              query: (q) => q.from('users'),
              mapper: TestUser.fromMap,
              loadingBuilder: (context) => const Text('No Database'),
              errorBuilder: (context, error) => Text('Error: $error'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      expect(find.text('No Database'), findsOneWidget);
    });

    testWidgets('passes through ListView properties', (WidgetTester tester) async {
      const testPadding = EdgeInsets.all(16.0);
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueryListView<TestUser>(
              database: database,
              query: (q) => q.from('users'),
              mapper: TestUser.fromMap,
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => Text('Error: $error'),
              itemBuilder: (context, user) => Text(user.name),
              // ListView properties
              padding: testPadding,
              scrollDirection: Axis.vertical,
              reverse: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.padding, equals(testPadding));
      expect(listView.scrollDirection, equals(Axis.vertical));
      expect(listView.reverse, equals(false));
      expect(listView.shrinkWrap, equals(true));
      expect(listView.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets('handles errors gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QueryListView<TestUser>(
              database: database,
              query: (q) => q.from('nonexistent_table'), // This should cause an error
              mapper: TestUser.fromMap,
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => Text('Database Error'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      expect(find.text('Database Error'), findsOneWidget);
    });

    testWidgets('works with DatabaseProvider integration', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider(
            schema: (builder) {
              builder.table('users', (table) {
                table.guid('id').notNull();
                table.text('name').notNull();
                table.text('email').notNull();
                table.integer('age').notNull(0);
                table.key(['id']).primary();
              });
            },
            databaseName: 'integration_test.db',
            child: Scaffold(
              body: Builder(
                builder: (context) => QueryListView<TestUser>(
                  database: DatabaseProvider.of(context),
                  query: (q) => q.from('users'),
                  mapper: TestUser.fromMap,
                  loadingBuilder: (context) => const Text('Loading...'),
                  errorBuilder: (context, error) => Text('Error: $error'),
                  itemBuilder: (context, user) => Text(user.name),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Should successfully initialize and show empty list
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}