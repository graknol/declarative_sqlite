import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'in_memory_file_repository.dart';

// Mock data and schema for testing
void buildTestSchema(SchemaBuilder builder) {
  builder.table('users', (table) {
    table.guid('id');
    table.text('name');
    table.integer('age');
  });
}

class User extends DbRecord {
  User(super.row, super.db);

  String get name => getValue('name')!;
  int get age => getValue('age')!;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseProvider', () {
    testWidgets('provides a database to its descendants',
        (WidgetTester tester) async {
      final db = await DeclarativeDatabase.open(
        ':memory:',
        schema: Schema.fromBuilder(buildTestSchema),
        databaseFactory: databaseFactory,
        fileRepository: InMemoryFileRepository(),
      );
      addTearDown(() => db.close());

      late DeclarativeDatabase? providedDb;

      await tester.pumpWidget(
        DatabaseProvider.value(
          database: db,
          child: Builder(
            builder: (context) {
              providedDb = DatabaseProvider.of(context);
              return Container();
            },
          ),
        ),
      );

      expect(providedDb, isNotNull);
      expect(providedDb, same(db));
    });

    testWidgets('of() throws if no provider is found',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            expect(
              () => DatabaseProvider.of(context),
              throwsA(isA<FlutterError>()),
            );
            return Container();
          },
        ),
      );
    });

    testWidgets('maybeOf() returns null if no provider is found',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            final db = DatabaseProvider.maybeOf(context);
            expect(db, isNull);
            return Container();
          },
        ),
      );
    });
  });

  group('QueryListView', () {
    late DeclarativeDatabase db;

    setUp(() async {
      db = await DeclarativeDatabase.open(
        ':memory:',
        schema: Schema.fromBuilder(buildTestSchema),
        databaseFactory: databaseFactory,
        fileRepository: InMemoryFileRepository(),
      );
      await db.insert('users', {'id': '1', 'name': 'Alice', 'age': 30});
      await db.insert('users', {'id': '2', 'name': 'Bob', 'age': 25});
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('displays loading state initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider.value(
            database: db,
            child: QueryListView<User>(
              query: (q) => q.from('users'),
              mapper: (row, db) => User(row, db),
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => Text('Error: $error'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      // The first frame is always the loading state
      expect(find.text('Loading...'), findsOneWidget);

      // Pump a frame to allow the stream to deliver its first result
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('displays items after loading', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider.value(
            database: db,
            child: QueryListView<User>(
              query: (q) => q.from('users'),
              mapper: (row, db) => User(row, db),
              loadingBuilder: (context) => const CircularProgressIndicator(),
              errorBuilder: (context, error) => const Text('Error'),
              itemBuilder: (context, user) => ListTile(title: Text(user.name)),
            ),
          ),
        ),
      );

      await tester.pump(); // Let stream emit

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('updates when database changes', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider.value(
            database: db,
            child: QueryListView<User>(
              query: (q) => q.from('users'),
              mapper: (row, db) => User(row, db),
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => Text('Error: $error'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Add a new user
      await db.insert('users', {'id': '3', 'name': 'Charlie', 'age': 35});
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('displays error state on query failure',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseProvider.value(
            database: db,
            child: QueryListView<User>(
              query: (q) => q.from('non_existent_table'), // Invalid query
              mapper: (row, db) => User(row, db),
              loadingBuilder: (context) => const Text('Loading...'),
              errorBuilder: (context, error) => const Text('Error occurred'),
              itemBuilder: (context, user) => Text(user.name),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Error occurred'), findsOneWidget);
    });
  });
}
