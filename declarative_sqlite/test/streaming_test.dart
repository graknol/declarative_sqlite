import 'dart:async';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late DeclarativeDatabase db;

  Schema getSchema() {
    final schemaBuilder = SchemaBuilder();
    
    schemaBuilder.table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.integer('age').notNull(0);
      table.text('status').notNull('active');
      table.key(['id']).primary();
    });
    
    schemaBuilder.table('posts', (table) {
      table.integer('id').notNull(0);
      table.integer('user_id').notNull(0);
      table.text('title').notNull('');
      table.text('content').notNull('');
      table.key(['id']).primary();
    });
    
    return schemaBuilder.build();
  }

  setUpAll(() async {
    db = await setupTestDatabase(schema: getSchema());
  });

  setUp(() async {
    await clearDatabase(db.db);
  });

  tearDownAll(() async {
    await db.close();
  });

  group('QueryDependencyAnalyzer', () {
    test('analyzes simple SELECT query dependencies using schema', () {
      final analyzer = QueryDependencyAnalyzer(getSchema());
      final builder = QueryBuilder().from('users');
      final dependencies = analyzer.analyze(builder);
      
      expect(dependencies.tables, contains('users'));
      expect(dependencies.usesWildcard, isTrue);
    });

    test('analyzes query with specific columns using schema validation', () {
      final analyzer = QueryDependencyAnalyzer(getSchema());
      final builder = QueryBuilder()
          .select('id')
          .select('name')
          .from('users');
      final dependencies = analyzer.analyze(builder);
      
      expect(dependencies.tables, contains('users'));
      expect(dependencies.columns, contains('users.id'));
      expect(dependencies.columns, contains('users.name'));
      expect(dependencies.usesWildcard, isFalse);
    });

    test('analyzes query with JOINs using schema metadata', () {
      final analyzer = QueryDependencyAnalyzer(getSchema());
      final builder = QueryBuilder()
          .select('u.name')
          .select('p.title')
          .from('users', 'u')
          .leftJoin('posts', 'u.id = p.user_id', 'p');
      final dependencies = analyzer.analyze(builder);
      
      expect(dependencies.tables, containsAll(['users', 'posts']));
      expect(dependencies.columns, contains('u.name'));
      expect(dependencies.columns, contains('p.title'));
    });

    test('validates columns against schema', () {
      final analyzer = QueryDependencyAnalyzer(getSchema());
      final builder = QueryBuilder()
          .select('id')
          .select('invalid_column')  // This column doesn't exist in schema
          .from('users');
      final dependencies = analyzer.analyze(builder);
      
      expect(dependencies.tables, contains('users'));
      expect(dependencies.columns, contains('users.id'));
      // Invalid column should not be included in dependencies
      expect(dependencies.columns, isNot(contains('users.invalid_column')));
    });

    test('handles system columns correctly', () {
      final analyzer = QueryDependencyAnalyzer(getSchema());
      final builder = QueryBuilder()
          .select('system_id')
          .select('system_version')
          .from('users');
      final dependencies = analyzer.analyze(builder);
      
      expect(dependencies.tables, contains('users'));
      // System columns should be recognized as valid
      expect(dependencies.columns, contains('users.system_id'));
      expect(dependencies.columns, contains('users.system_version'));
    });

    test('analyzes QueryBuilder structure directly without SQL generation', () {
      final analyzer = QueryDependencyAnalyzer(getSchema());
      
      // Create a complex QueryBuilder with JOINs and subqueries
      final builder = QueryBuilder()
          .select('u.name')
          .select('p.title')
          .selectSubQuery((sub) => sub
              .select('COUNT(*)')
              .from('posts')
              .where(col('user_id').eq('u.id')), 'post_count')
          .from('users', 'u')
          .leftJoin('posts', 'u.id = p.user_id', 'p');
          
      final dependencies = analyzer.analyze(builder);
      
      // Should detect all tables including those in subqueries
      expect(dependencies.tables, containsAll(['users', 'posts']));
      expect(dependencies.columns, contains('u.name'));
      expect(dependencies.columns, contains('p.title'));
    });

    test('recursive analysis of QueryBuilder and Views produces unified dependencies', () {
      // Create a schema with a view that has complex dependencies
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('users', (table) {
        table.integer('id').notNull(0);
        table.text('name').notNull('');
        table.key(['id']).primary();
      });
      schemaBuilder.table('posts', (table) {
        table.integer('id').notNull(0);
        table.integer('user_id').notNull(0);
        table.text('title').notNull('');
        table.key(['id']).primary();
      });
      schemaBuilder.table('comments', (table) {
        table.integer('id').notNull(0);
        table.integer('post_id').notNull(0);
        table.text('content').notNull('');
        table.key(['id']).primary();
      });
      // View that joins users and posts
      schemaBuilder.view('user_posts', (view) {
        view.select('u.name, p.title').from('users', 'u').leftJoin('posts', 'u.id = p.user_id', 'p');
      });
      final schema = schemaBuilder.build();
      
      final analyzer = QueryDependencyAnalyzer(schema);
      
      // QueryBuilder that uses the view AND additional tables
      final builder = QueryBuilder()
          .select('up.name')
          .select('c.content')
          .from('user_posts', 'up')
          .leftJoin('comments', 'up.post_id = c.post_id', 'c');
          
      final dependencies = analyzer.analyze(builder);
      
      // Should include:
      // - Direct dependencies from QueryBuilder: user_posts, comments
      // - Recursive dependencies from user_posts view: users, posts
      expect(dependencies.tables, containsAll(['user_posts', 'comments', 'users', 'posts']));
    });

    test('analyzes view dependencies recursively', () {
      // Create a schema with a view that depends on users table
      final schemaBuilder = SchemaBuilder();
      schemaBuilder.table('users', (table) {
        table.integer('id').notNull(0);
        table.text('name').notNull('');
        table.text('status').notNull('active');
        table.key(['id']).primary();
      });
      schemaBuilder.view('active_users', (view) {
        view.select('*').from('users');
      });
      final schema = schemaBuilder.build();
      
      final analyzer = QueryDependencyAnalyzer(schema);
      final builder = QueryBuilder().from('active_users');
      final dependencies = analyzer.analyze(builder);
      
      expect(dependencies.tables, contains('active_users'));
      // Should also detect the underlying users table dependency  
      expect(dependencies.tables, contains('users'));
    });
  });

  group('StreamingQuery', () {
    test('emits initial results when subscribed', () async {
      // Insert test data
      await db.insert('users', {'id': 1, 'name': 'Alice', 'age': 30, 'status': 'active'});
      await db.insert('users', {'id': 2, 'name': 'Bob', 'age': 25, 'status': 'active'});

      final completer = Completer<List<Map<String, Object?>>>();
      
      final stream = db.stream<Map<String, Object?>>(
        (q) => q.from('users').where(col('status').eq('active')),
        (row) => row,
      );

      late StreamSubscription subscription;
      subscription = stream.listen((results) {
        if (!completer.isCompleted) {
          completer.complete(results);
          subscription.cancel();
        }
      });

      final results = await completer.future;
      expect(results.length, 2);
      expect(results[0]['name'], anyOf('Alice', 'Bob'));
      expect(results[1]['name'], anyOf('Alice', 'Bob'));
    });

    test('emits updated results when data changes', () async {
      // Insert initial data
      await db.insert('users', {'id': 1, 'name': 'Alice', 'age': 30, 'status': 'active'});

      final resultsList = <List<Map<String, Object?>>>[];
      final completer = Completer<void>();
      
      final stream = db.stream<Map<String, Object?>>(
        (q) => q.from('users').where(col('status').eq('active')),
        (row) => row,
      );

      late StreamSubscription subscription;
      subscription = stream.listen((results) {
        resultsList.add(results);
        
        if (resultsList.length == 3) {
          completer.complete();
          subscription.cancel();
        }
      });

      // Wait for initial result
      await Future.delayed(Duration(milliseconds: 50));
      
      // Insert new data - should trigger stream update
      await db.insert('users', {'id': 2, 'name': 'Bob', 'age': 25, 'status': 'active'});
      
      // Wait a bit then insert another
      await Future.delayed(Duration(milliseconds: 50));
      await db.insert('users', {'id': 3, 'name': 'Charlie', 'age': 35, 'status': 'inactive'});

      await completer.future;

      // Should have 3 emissions: initial, after Bob insert, after Charlie insert
      expect(resultsList.length, 3);
      
      // Initial: just Alice
      expect(resultsList[0].length, 1);
      expect(resultsList[0][0]['name'], 'Alice');
      
      // After Bob: Alice + Bob  
      expect(resultsList[1].length, 2);
      
      // After Charlie: still Alice + Bob (Charlie has status 'inactive')
      expect(resultsList[2].length, 2);
    });

    test('emits updated results when data is updated', () async {
      // Insert initial data
      await db.insert('users', {'id': 1, 'name': 'Alice', 'age': 30, 'status': 'active'});

      final resultsList = <List<Map<String, Object?>>>[];
      final completer = Completer<void>();
      
      final stream = db.stream<Map<String, Object?>>(
        (q) => q.from('users').where(col('status').eq('active')),
        (row) => row,
      );

      late StreamSubscription subscription;
      subscription = stream.listen((results) {
        resultsList.add(results);
        
        if (resultsList.length == 2) {
          completer.complete();
          subscription.cancel();
        }
      });

      // Wait for initial result
      await Future.delayed(Duration(milliseconds: 50));
      
      // Update status - should trigger stream update  
      await db.update(
        'users',
        {'status': 'inactive'},
        where: 'id = ?',
        whereArgs: [1],
      );

      await completer.future;

      // Should have 2 emissions: initial with Alice, then empty after status change
      expect(resultsList.length, 2);
      expect(resultsList[0].length, 1); // Alice initially active
      expect(resultsList[1].length, 0); // Alice now inactive, filtered out
    });

    test('emits updated results when data is deleted', () async {
      // Insert initial data
      await db.insert('users', {'id': 1, 'name': 'Alice', 'age': 30, 'status': 'active'});
      await db.insert('users', {'id': 2, 'name': 'Bob', 'age': 25, 'status': 'active'});

      final resultsList = <List<Map<String, Object?>>>[];
      final completer = Completer<void>();
      
      final stream = db.stream<Map<String, Object?>>(
        (q) => q.from('users').where(col('status').eq('active')),
        (row) => row,
      );

      late StreamSubscription subscription;
      subscription = stream.listen((results) {
        resultsList.add(results);
        
        if (resultsList.length == 2) {
          completer.complete();
          subscription.cancel();
        }
      });

      // Wait for initial result
      await Future.delayed(Duration(milliseconds: 50));
      
      // Delete one user
      await db.delete('users', where: 'id = ?', whereArgs: [1]);

      await completer.future;

      // Should have 2 emissions: initial with both users, then just Bob
      expect(resultsList.length, 2);
      expect(resultsList[0].length, 2); // Both users initially
      expect(resultsList[1].length, 1); // Just Bob after Alice deleted
      expect(resultsList[1][0]['name'], 'Bob');
    });

    test('emits updated results after bulkLoad', () async {
      final resultsList = <List<Map<String, Object?>>>[];
      final completer = Completer<void>();
      
      final stream = db.stream<Map<String, Object?>>(
        (q) => q.from('users'),
        (row) => row,
      );

      late StreamSubscription subscription;
      subscription = stream.listen((results) {
        resultsList.add(results);
        
        if (resultsList.length == 2) {
          completer.complete();
          subscription.cancel();
        }
      });

      // Wait for initial result (should be empty)
      await Future.delayed(Duration(milliseconds: 50));
      
      // Bulk load data
      await db.bulkLoad('users', [
        {
          'id': 1,
          'name': 'Alice',
          'age': 30,
          'status': 'active',
          'system_id': 'alice-123',
        },
        {
          'id': 2,
          'name': 'Bob', 
          'age': 25,
          'status': 'active',
          'system_id': 'bob-456',
        },
      ]);

      await completer.future;

      expect(resultsList.length, 2);
      expect(resultsList[0].length, 0); // Initially empty
      expect(resultsList[1].length, 2); // After bulk load
    });

    test('multiple streams work independently', () async {
      await db.insert('users', {'id': 1, 'name': 'Alice', 'age': 30, 'status': 'active'});
      await db.insert('users', {'id': 2, 'name': 'Bob', 'age': 25, 'status': 'inactive'});

      final activeResults = <List<Map<String, Object?>>>[];
      final allResults = <List<Map<String, Object?>>>[];
      
      final activeStream = db.stream<Map<String, Object?>>(
        (q) => q.from('users').where(col('status').eq('active')),
        (row) => row,
      );
      
      final allStream = db.stream<Map<String, Object?>>(
        (q) => q.from('users'),
        (row) => row,
      );

      final activeSubscription = activeStream.listen(activeResults.add);
      final allSubscription = allStream.listen(allResults.add);

      // Wait for initial results
      await Future.delayed(Duration(milliseconds: 50));
      
      // Insert new active user
      await db.insert('users', {'id': 3, 'name': 'Charlie', 'age': 35, 'status': 'active'});
      
      await Future.delayed(Duration(milliseconds: 50));

      activeSubscription.cancel();
      allSubscription.cancel();

      // Active stream should show Alice initially, then Alice + Charlie
      expect(activeResults.length, 2);
      expect(activeResults[0].length, 1); // Just Alice
      expect(activeResults[1].length, 2); // Alice + Charlie
      
      // All stream should show Alice + Bob initially, then Alice + Bob + Charlie
      expect(allResults.length, 2);
      expect(allResults[0].length, 2); // Alice + Bob
      expect(allResults[1].length, 3); // Alice + Bob + Charlie
    });

    test('stream stops emitting after cancellation', () async {
      await db.insert('users', {'id': 1, 'name': 'Alice', 'age': 30, 'status': 'active'});

      final results = <List<Map<String, Object?>>>[];
      
      final stream = db.stream<Map<String, Object?>>(
        (q) => q.from('users'),
        (row) => row,
      );

      final subscription = stream.listen(results.add);

      // Wait for initial result
      await Future.delayed(Duration(milliseconds: 50));
      
      // Cancel subscription
      subscription.cancel();
      
      // Wait a bit then insert data
      await Future.delayed(Duration(milliseconds: 50));
      await db.insert('users', {'id': 2, 'name': 'Bob', 'age': 25, 'status': 'active'});
      
      // Wait to see if any more results come through
      await Future.delayed(Duration(milliseconds: 100));

      // Should only have the initial result, not the one after cancellation
      expect(results.length, 1);
    });
  });
}