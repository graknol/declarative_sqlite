import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'test_helper.dart';

void main() {
  group('Integration Tests', () {
    testWidgets('DatabaseProvider + QueryListView integration', (WidgetTester tester) async {
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
              appBar: AppBar(title: const Text('Users')),
              body: Builder(
                builder: (context) => QueryListView<TestUser>(
                  database: DatabaseProvider.of(context),
                  query: (q) => q.from('users').orderBy('name'),
                  mapper: TestUser.fromMap,
                  loadingBuilder: (context) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  errorBuilder: (context, error) => Center(
                    child: Text('Error: $error'),
                  ),
                  itemBuilder: (context, user) => ListTile(
                    title: Text(user.name),
                    subtitle: Text(user.email),
                    trailing: Text('${user.age}'),
                  ),
                ),
              ),
              floatingActionButton: Builder(
                builder: (context) => FloatingActionButton(
                  onPressed: () async {
                    final db = DatabaseProvider.of(context);
                    await db.insert('users', {
                      'id': 'user${DateTime.now().millisecondsSinceEpoch}',
                      'name': 'Test User',
                      'email': 'test@example.com',
                      'age': 25,
                    });
                  },
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Should show the app
      expect(find.text('Users'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Initially no users
      expect(find.text('Test User'), findsNothing);

      // Add a user
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await waitForAsync();

      // Should automatically show the new user
      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
    });

    testWidgets('DatabaseProvider + ServerSyncManagerWidget + QueryListView integration', (WidgetTester tester) async {
      bool fetchCalled = false;
      bool sendCalled = false;
      List<DirtyRow> capturedOperations = [];

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
            databaseName: 'full_integration_test.db',
            child: ServerSyncManagerWidget(
              retryStrategy: null,
              fetchInterval: const Duration(minutes: 5),
              onFetch: (db, table, lastSynced) async {
                fetchCalled = true;
                // Simulate fetching data from server
                if (table == 'users') {
                  await db.insert('users', {
                    'id': 'server_user',
                    'name': 'Server User',
                    'email': 'server@example.com',
                    'age': 30,
                  });
                }
              },
              onSend: (operations) async {
                sendCalled = true;
                capturedOperations = operations;
                return true;
              },
              child: Scaffold(
                appBar: AppBar(title: const Text('Synced Users')),
                body: Builder(
                  builder: (context) => QueryListView<TestUser>(
                    database: DatabaseProvider.of(context),
                    query: (q) => q.from('users').orderBy('name'),
                    mapper: TestUser.fromMap,
                    loadingBuilder: (context) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorBuilder: (context, error) => Center(
                      child: Text('Error: $error'),
                    ),
                    itemBuilder: (context, user) => ListTile(
                      title: Text(user.name),
                      subtitle: Text(user.email),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final db = DatabaseProvider.of(context);
                          await db.delete('users', where: 'id = ?', whereArgs: [user.id]);
                        },
                      ),
                    ),
                  ),
                ),
                floatingActionButton: Builder(
                  builder: (context) => FloatingActionButton(
                    onPressed: () async {
                      final db = DatabaseProvider.of(context);
                      await db.insert('users', {
                        'id': 'local_user_${DateTime.now().millisecondsSinceEpoch}',
                        'name': 'Local User',
                        'email': 'local@example.com',
                        'age': 25,
                      });
                    },
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Should show the app
      expect(find.text('Synced Users'), findsOneWidget);

      // Add a local user
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await waitForAsync();

      // Should show the local user
      expect(find.text('Local User'), findsOneWidget);
    });

    testWidgets('error handling across all widgets', (WidgetTester tester) async {
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
            databaseName: 'error_test.db',
            child: ServerSyncManagerWidget(
              retryStrategy: null,
              fetchInterval: const Duration(minutes: 5),
              onFetch: (db, table, lastSynced) async {
                // Simulate fetch error
                throw Exception('Fetch failed');
              },
              onSend: (operations) async {
                // Simulate send error
                throw Exception('Send failed');
              },
              child: Scaffold(
                body: Builder(
                  builder: (context) => QueryListView<TestUser>(
                    database: DatabaseProvider.of(context),
                    query: (q) => q.from('nonexistent_table'), // This will cause an error
                    mapper: TestUser.fromMap,
                    loadingBuilder: (context) => const Text('Loading...'),
                    errorBuilder: (context, error) => const Text('Query Error'),
                    itemBuilder: (context, user) => Text(user.name),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Should handle errors gracefully
      expect(find.text('Query Error'), findsOneWidget);
    });

    testWidgets('dynamic configuration changes', (WidgetTester tester) async {
      bool useComplexQuery = false;

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
              builder.table('posts', (table) {
                table.guid('id').notNull();
                table.guid('user_id').notNull();
                table.text('title').notNull();
                table.text('content').notNull();
                table.key(['id']).primary();
              });
            },
            databaseName: 'dynamic_test.db',
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                appBar: AppBar(
                  title: const Text('Dynamic Test'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.toggle_on),
                      onPressed: () {
                        setState(() {
                          useComplexQuery = !useComplexQuery;
                        });
                      },
                    ),
                  ],
                ),
                body: QueryListView<dynamic>(
                  database: DatabaseProvider.of(context),
                  query: (q) => useComplexQuery
                      ? q.from('users').join('posts', 'users.id = posts.user_id')
                      : q.from('users'),
                  mapper: (map) => map,
                  loadingBuilder: (context) => const Text('Loading...'),
                  errorBuilder: (context, error) => Text('Error: $error'),
                  itemBuilder: (context, item) => ListTile(
                    title: Text('${item['name'] ?? 'Unknown'}'),
                  ),
                ),
                floatingActionButton: FloatingActionButton(
                  onPressed: () async {
                    final db = DatabaseProvider.of(context);
                    final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
                    await db.insert('users', {
                      'id': userId,
                      'name': 'Dynamic User',
                      'email': 'dynamic@example.com',
                      'age': 25,
                    });
                    if (useComplexQuery) {
                      await db.insert('posts', {
                        'id': 'post_${DateTime.now().millisecondsSinceEpoch}',
                        'user_id': userId,
                        'title': 'Dynamic Post',
                        'content': 'Content',
                      });
                    }
                  },
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Should show the app
      expect(find.text('Dynamic Test'), findsOneWidget);

      // Add some data
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await waitForAsync();

      expect(find.text('Dynamic User'), findsOneWidget);

      // Toggle query complexity
      await tester.tap(find.byIcon(Icons.toggle_on));
      await tester.pumpAndSettle();
      await waitForAsync();

      // Should still work with complex query
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('performance with large datasets', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider(
            schema: (builder) {
              builder.table('items', (table) {
                table.integer('id').notNull();
                table.text('name').notNull();
                table.key(['id']).primary();
              });
            },
            databaseName: 'performance_test.db',
            child: Scaffold(
              body: Builder(
                builder: (context) => QueryListView<Map<String, Object?>>(
                  database: DatabaseProvider.of(context),
                  query: (q) => q.from('items').orderBy('id'),
                  mapper: (map) => map,
                  loadingBuilder: (context) => const Text('Loading...'),
                  errorBuilder: (context, error) => Text('Error: $error'),
                  itemBuilder: (context, item) => ListTile(
                    title: Text('${item['name']}'),
                  ),
                ),
              ),
              floatingActionButton: Builder(
                builder: (context) => FloatingActionButton(
                  onPressed: () async {
                    final db = DatabaseProvider.of(context);
                    // Insert multiple items at once
                    for (int i = 1; i <= 100; i++) {
                      await db.insert('items', {
                        'id': i,
                        'name': 'Item $i',
                      });
                    }
                  },
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await waitForAsync();

      // Add many items
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await waitForAsync(const Duration(seconds: 1)); // Give more time for large dataset

      // Should handle large datasets without issues
      expect(find.byType(ListView), findsOneWidget);
      // Check that at least some items are visible
      expect(find.textContaining('Item'), findsWidgets);
    });
  });
}