import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'test_helper.dart';

void main() {
  group('DatabaseProvider', () {
    testWidgets('provides database to descendant widgets', (WidgetTester tester) async {
      DeclarativeDatabase? capturedDatabase;
      
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
            databaseName: 'test.db',
            child: Builder(
              builder: (context) {
                capturedDatabase = DatabaseProvider.maybeOf(context);
                return const Text('Test');
              },
            ),
          ),
        ),
      );

      // Wait for database initialization
      await tester.pumpAndSettle();

      expect(capturedDatabase, isNotNull);
      expect(capturedDatabase, isA<DeclarativeDatabase>());

      // Clean up
      await capturedDatabase?.close();
    });

    testWidgets('DatabaseProvider.of throws when no provider found', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(
                () => DatabaseProvider.of(context),
                throwsA(isA<FlutterError>()),
              );
              return const Text('Test');
            },
          ),
        ),
      );
    });

    testWidgets('DatabaseProvider.maybeOf returns null when no provider found', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final database = DatabaseProvider.maybeOf(context);
              expect(database, isNull);
              return const Text('Test');
            },
          ),
        ),
      );
    });

    testWidgets('rebuilds when database configuration changes', (WidgetTester tester) async {
      DeclarativeDatabase? firstDatabase;
      DeclarativeDatabase? secondDatabase;
      
      // First configuration
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
            databaseName: 'test1.db',
            child: Builder(
              builder: (context) {
                firstDatabase = DatabaseProvider.maybeOf(context);
                return const Text('Test');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(firstDatabase, isNotNull);

      // Change database name
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
            databaseName: 'test2.db',
            child: Builder(
              builder: (context) {
                secondDatabase = DatabaseProvider.maybeOf(context);
                return const Text('Test');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(secondDatabase, isNotNull);
      expect(secondDatabase, isNot(equals(firstDatabase)));

      // Clean up
      await firstDatabase?.close();
      await secondDatabase?.close();
    });

    testWidgets('handles database initialization errors gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider(
            schema: (builder) {
              // Invalid schema that should cause an error
              builder.table('', (table) {
                // Empty table name should cause issues
              });
            },
            databaseName: 'test.db',
            child: const Text('Test'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show an error widget instead of crashing
      expect(find.byType(ErrorWidget), findsOneWidget);
    });

    testWidgets('properly disposes database on widget disposal', (WidgetTester tester) async {
      DeclarativeDatabase? database;
      
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
            databaseName: 'test.db',
            child: Builder(
              builder: (context) {
                database = DatabaseProvider.maybeOf(context);
                return const Text('Test');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(database, isNotNull);

      // Remove the widget tree
      await tester.pumpWidget(const MaterialApp(home: Text('Empty')));
      await tester.pumpAndSettle();

      // Database should be properly closed
      // Note: We can't directly test if the database is closed,
      // but we can ensure no exceptions are thrown during disposal
    });

    testWidgets('supports custom database path', (WidgetTester tester) async {
      DeclarativeDatabase? database;
      const customPath = '/custom/path/test.db';
      
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
            databaseName: 'test.db',
            databasePath: customPath,
            child: Builder(
              builder: (context) {
                database = DatabaseProvider.maybeOf(context);
                return const Text('Test');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(database, isNotNull);

      // Clean up
      await database?.close();
    });

    testWidgets('shows loading state during initialization', (WidgetTester tester) async {
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
            databaseName: 'test.db',
            child: const Text('Test Content'),
          ),
        ),
      );

      // Initially should show nothing (SizedBox.shrink)
      expect(find.text('Test Content'), findsNothing);
      
      // After settling, should show the content
      await tester.pumpAndSettle();
      expect(find.text('Test Content'), findsOneWidget);
    });
  });
}