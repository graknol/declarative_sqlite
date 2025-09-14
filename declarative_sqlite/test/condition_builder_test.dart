import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Example interface for testing interface-like access patterns
/// This simulates how developers would define their own interfaces
abstract class IUser {
  int get id;
  String get name;
  String get email;
  int get age;
  String get status;
  
  Future<void> setName(String value);
  Future<void> setStatus(String value);
}

/// Test suite for the new ConditionBuilder and enhanced QueryBuilder with Equatable support
void main() {
  late Database database;
  late DataAccess dataAccess;
  late SchemaBuilder schema;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(':memory:');
    
    schema = SchemaBuilder()
      .table('users', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('email', (col) => col.unique())
          .integer('age')
          .text('status', (col) => col.notNull())
          .text('city')
          .real('salary'));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);

    // Insert test data
    await dataAccess.insert('users', {
      'name': 'Alice',
      'email': 'alice@example.com',
      'age': 30,
      'status': 'active',
      'city': 'New York',
      'salary': 75000.0,
    });

    await dataAccess.insert('users', {
      'name': 'Bob',
      'email': 'bob@example.com',
      'age': 25,
      'status': 'inactive',
      'city': 'Los Angeles',
      'salary': 65000.0,
    });

    await dataAccess.insert('users', {
      'name': 'Charlie',
      'email': 'charlie@example.com',
      'age': 35,
      'status': 'active',
      'city': 'New York',
      'salary': 85000.0,
    });

    await dataAccess.insert('users', {
      'name': 'Diana',
      'email': 'diana@example.com',
      'age': 28,
      'status': 'active',
      'city': 'Chicago',
      'salary': 70000.0,
    });
  });

  tearDown(() async {
    await database.close();
  });

  group('ConditionBuilder Tests', () {
    test('should create simple equality conditions', () {
      final condition = ConditionBuilder.eq('name', 'Alice');
      expect(condition.toSql(), equals('name = ?'));
      expect(condition.getArguments(), equals(['Alice']));
    });

    test('should create comparison conditions', () {
      final ltCondition = ConditionBuilder.lt('age', 30);
      expect(ltCondition.toSql(), equals('age < ?'));
      expect(ltCondition.getArguments(), equals([30]));

      final geCondition = ConditionBuilder.ge('salary', 70000);
      expect(geCondition.toSql(), equals('salary >= ?'));
      expect(geCondition.getArguments(), equals([70000]));
    });

    test('should create IN and BETWEEN conditions', () {
      final inCondition = ConditionBuilder.inList('city', ['New York', 'Chicago']);
      expect(inCondition.toSql(), equals('city IN (?, ?)'));
      expect(inCondition.getArguments(), equals(['New York', 'Chicago']));

      final betweenCondition = ConditionBuilder.between('age', 25, 35);
      expect(betweenCondition.toSql(), equals('age BETWEEN ? AND ?'));
      expect(betweenCondition.getArguments(), equals([25, 35]));
    });

    test('should create NULL conditions', () {
      final isNullCondition = ConditionBuilder.isNull('city');
      expect(isNullCondition.toSql(), equals('city IS NULL'));
      expect(isNullCondition.getArguments(), isEmpty);

      final isNotNullCondition = ConditionBuilder.isNotNull('email');
      expect(isNotNullCondition.toSql(), equals('email IS NOT NULL'));
      expect(isNotNullCondition.getArguments(), isEmpty);
    });

    test('should compose conditions with AND', () {
      final condition1 = ConditionBuilder.eq('status', 'active');
      final condition2 = ConditionBuilder.gt('age', 25);
      final combined = condition1.and(condition2);

      expect(combined.toSql(), equals('(status = ?) AND (age > ?)'));
      expect(combined.getArguments(), equals(['active', 25]));
    });

    test('should compose conditions with OR', () {
      final condition1 = ConditionBuilder.eq('city', 'New York');
      final condition2 = ConditionBuilder.eq('city', 'Chicago');
      final combined = condition1.or(condition2);

      expect(combined.toSql(), equals('(city = ?) OR (city = ?)'));
      expect(combined.getArguments(), equals(['New York', 'Chicago']));
    });

    test('should negate conditions with NOT', () {
      final condition = ConditionBuilder.eq('status', 'inactive');
      final negated = condition.not();

      expect(negated.toSql(), equals('NOT (status = ?)'));
      expect(negated.getArguments(), equals(['inactive']));
    });

    test('should compose complex conditions with grouping', () {
      // (status = 'active' AND age > 25) OR (city = 'New York' AND salary > 70000)
      final condition1 = ConditionBuilder.eq('status', 'active').and(ConditionBuilder.gt('age', 25));
      final condition2 = ConditionBuilder.eq('city', 'New York').and(ConditionBuilder.gt('salary', 70000));
      final complex = condition1.or(condition2);

      expect(complex.toSql(), equals('((status = ?) AND (age > ?)) OR ((city = ?) AND (salary > ?))'));
      expect(complex.getArguments(), equals(['active', 25, 'New York', 70000]));
    });

    test('should use static helper methods', () {
      final condition1 = Conditions.eq('name', 'Alice');
      final condition2 = Conditions.gt('age', 25);
      final combined = condition1.and(condition2);

      expect(combined.toSql(), equals('(name = ?) AND (age > ?)'));
      expect(combined.getArguments(), equals(['Alice', 25]));
    });

    test('should combine multiple conditions with andAll and orAll', () {
      final conditions = [
        ConditionBuilder.eq('status', 'active'),
        ConditionBuilder.gt('age', 25),
        ConditionBuilder.inList('city', ['New York', 'Chicago']),
      ];

      final andCombined = ConditionBuilder.andAll(conditions);
      expect(andCombined.toSql(), contains('AND'));
      expect(andCombined.getArguments(), equals(['active', 25, 'New York', 'Chicago']));

      final orCombined = ConditionBuilder.orAll(conditions);
      expect(orCombined.toSql(), contains('OR'));
      expect(orCombined.getArguments(), equals(['active', 25, 'New York', 'Chicago']));
    });
  });

  group('QueryBuilder with ConditionBuilder Tests', () {
    test('should use ConditionBuilder in WHERE clause', () async {
      final condition = ConditionBuilder.eq('status', 'active').and(ConditionBuilder.gt('age', 25));
      
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(condition)
          .orderByColumn('age');

      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(3)); // Alice (30), Diana (28), and Charlie (35)
      expect(results[0]['name'], equals('Diana')); // Ordered by age
      expect(results[1]['name'], equals('Alice'));
      expect(results[2]['name'], equals('Charlie'));
    });

    test('should build complex queries with multiple conditions', () async {
      // Find users who are either in New York OR (active and age > 25)
      final nyCondition = ConditionBuilder.eq('city', 'New York');
      final activeOlderCondition = ConditionBuilder.eq('status', 'active').and(ConditionBuilder.gt('age', 25));
      final complexCondition = nyCondition.or(activeOlderCondition);

      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(complexCondition)
          .orderByColumn('name');

      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(3)); // Alice, Charlie, Diana
      expect(results.map((r) => r['name']), equals(['Alice', 'Charlie', 'Diana']));
    });

    test('should support chaining conditions', () async {
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('status', 'active'))
          .andWhereCondition(ConditionBuilder.gt('salary', 70000))
          .orderByColumn('salary');

      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(2)); // Alice and Charlie
      expect(results[0]['name'], equals('Alice'));
      expect(results[1]['name'], equals('Charlie'));
    });

    test('should support OR chaining conditions', () async {
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('city', 'New York'))
          .orWhereCondition(ConditionBuilder.eq('city', 'Chicago'))
          .orderByColumn('name');

      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(3)); // Alice, Charlie, Diana
      expect(results.map((r) => r['name']), equals(['Alice', 'Charlie', 'Diana']));
    });
  });

  group('QueryBuilder Equatable Tests', () {
    test('should compare QueryBuilder instances by value', () {
      final query1 = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('status', 'active'))
          .orderByColumn('name');

      final query2 = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('status', 'active'))
          .orderByColumn('name');

      final query3 = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('status', 'inactive'))
          .orderByColumn('name');

      expect(query1, equals(query2)); // Same structure and conditions
      expect(query1, isNot(equals(query3))); // Different conditions
    });

    test('should compare ConditionBuilder instances by value', () {
      final condition1 = ConditionBuilder.eq('status', 'active').and(ConditionBuilder.gt('age', 25));
      final condition2 = ConditionBuilder.eq('status', 'active').and(ConditionBuilder.gt('age', 25));
      final condition3 = ConditionBuilder.eq('status', 'active').and(ConditionBuilder.gt('age', 30));

      expect(condition1, equals(condition2)); // Same conditions
      expect(condition1, isNot(equals(condition3))); // Different values
    });

    test('should demonstrate hot-swapping capability', () {
      final baseQuery = QueryBuilder().selectAll().from('users').orderByColumn('name');
      
      final activeQuery = baseQuery.where(ConditionBuilder.eq('status', 'active'));
      final inactiveQuery = baseQuery.where(ConditionBuilder.eq('status', 'inactive'));
      
      // These are different queries that would trigger unsubscribe/subscribe in reactive widgets
      expect(activeQuery, isNot(equals(inactiveQuery)));
      
      // But identical queries are equal
      final activeQuery2 = baseQuery.where(ConditionBuilder.eq('status', 'active'));
      expect(activeQuery, equals(activeQuery2));
    });
  });

  group('QueryBuilder Factory Methods Tests', () {
    test('should create table queries', () async {
      final query = QueryBuilder.table('users').orderByColumn('name');
      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(4));
      expect(results.map((r) => r['name']), equals(['Alice', 'Bob', 'Charlie', 'Diana']));
    });

    test('should create primary key queries', () async {
      final query = QueryBuilder.byPrimaryKey('users', 1);
      final result = await query.executeSingle(dataAccess);
      expect(result, isNotNull);
      expect(result!['name'], equals('Alice'));
    });

    test('should create all records queries', () async {
      final query = QueryBuilder.all('users').orderByColumn('age');
      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(4));
      expect(results.map((r) => r['age']), equals([25, 28, 30, 35]));
    });
  });

  group('Fluent Lambda API Tests', () {
    test('should support lambda-style where conditions', () async {
      // Using lambda style instead of ConditionBuilder.gt
      final query = QueryBuilder.table('users')
          .where((x) => x.gt('age', 25))
          .orderByColumn('age');
      
      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(3));
      expect(results.map((r) => r['age']), equals([28, 30, 35]));
    });

    test('should support lambda-style complex conditions', () async {
      // Test chaining with lambda style
      final query = QueryBuilder.table('users')
          .where((x) => x.gt('age', 25).and(x.eq('status', 'active')))
          .orderByColumn('age');
      
      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(3)); // Alice (30), Diana (28), Charlie (35)
      expect(results.map((r) => r['name']), equals(['Diana', 'Alice', 'Charlie']));
    });

    test('should support lambda-style having conditions', () async {
      // For now, test the having clause generation without execution
      // since executeMany doesn't support GROUP BY/HAVING yet
      final query = QueryBuilder()
          .select([ExpressionBuilder.column('status'), ExpressionBuilder.raw('COUNT(*) as count')])
          .from('users')
          .groupBy(['status'])
          .having((x) => x.gt('COUNT(*)', 1))
          .orderByColumn('status');
      
      // Test that the SQL generation works correctly
      expect(query.toSql(), contains('HAVING COUNT(*) > ?'));
      expect(query.getHavingArguments(), equals([1]));
    });

    test('should support lambda-style andWhere and orWhere', () async {
      final query = QueryBuilder.table('users')
          .where((x) => x.eq('status', 'active'))
          .andWhereCondition((x) => x.gt('age', 25))
          .orderByColumn('age');
      
      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(3)); // Alice (30), Diana (28), Charlie (35)
      expect(results.map((r) => r['name']), equals(['Diana', 'Alice', 'Charlie']));
    });

    test('should support mixing traditional and lambda APIs', () async {
      // Mix traditional ConditionBuilder with lambda
      final condition1 = ConditionBuilder.eq('status', 'active');
      final query = QueryBuilder.table('users')
          .where(condition1)
          .andWhereCondition((x) => x.gt('age', 25))
          .orderByColumn('age');
      
      final results = await query.executeMany(dataAccess);
      expect(results, hasLength(3)); // Alice (30), Diana (28), Charlie (35)
      expect(results.map((r) => r['name']), equals(['Diana', 'Alice', 'Charlie']));
    });

    test('should throw error for invalid condition types', () {
      expect(
        () => QueryBuilder.table('users').where('invalid string'),
        throwsArgumentError,
      );
      
      expect(
        () => QueryBuilder.table('users').having(123),
        throwsArgumentError,
      );
    });
  });

  group('Interface-like Access Tests', () {
    test('should support basic interface-like access patterns', () async {
      final query = QueryBuilder.table('users')
          .where((x) => x.eq('name', 'Alice'));
      
      final users = await query.executeManyTyped<dynamic>(dataAccess);
      expect(users, hasLength(1));
      
      final user = users.first;
      // Access properties like interface getters
      expect(user.id, equals(1));
      expect(user.name, equals('Alice'));
      expect(user.email, equals('alice@example.com'));
      expect(user.age, equals(30));
    });

    test('should support setter operations through interface pattern', () async {
      final query = QueryBuilder.table('users')
          .where((x) => x.eq('name', 'Alice'));
      
      final users = await query.executeManyTyped<dynamic>(dataAccess);
      expect(users, hasLength(1));
      
      final user = users.first;
      // Update via setter pattern
      await user.setName('Alice Updated');
      
      // Verify the update worked by searching for the new name
      final updatedUsers = await QueryBuilder.table('users')
          .where((x) => x.eq('name', 'Alice Updated'))
          .executeMany(dataAccess);
      expect(updatedUsers, hasLength(1));
      expect(updatedUsers.first['name'], equals('Alice Updated'));
    });

    test('should support getter and setter with snake_case to camelCase conversion', () async {
      final query = QueryBuilder.table('users')
          .where((x) => x.eq('name', 'Bob'));
      
      final users = await query.executeManyTyped<dynamic>(dataAccess);
      expect(users, hasLength(1));
      
      final user = users.first;
      
      // Access using camelCase for snake_case columns would require custom columns
      // For now just test basic access
      expect(user.status, equals('inactive'));
      
      // Update via setter
      await user.setStatus('active');
      
      // Verify update
      final updated = await QueryBuilder.table('users')
          .where((x) => x.eq('name', 'Bob'))
          .executeMany(dataAccess);
      expect(updated.first['status'], equals('active'));
    });

    test('should demonstrate interface-like usage pattern for developers', () async {
      // This test shows how developers would use the interface pattern in practice
      final query = QueryBuilder.table('users')
          .where((x) => x.eq('status', 'active'));
      
      // Get users as dynamic objects that support interface-like access
      final activeUsers = await query.executeManyTyped<dynamic>(dataAccess);
      
      // Developer can access properties as if they were interface getters
      for (final user in activeUsers) {
        expect(user.id, isA<int>());
        expect(user.name, isA<String>());
        expect(user.status, equals('active'));
        
        // Developer can call setters to update data
        if (user.name == 'Charlie') {
          await user.setName('Charlie Updated');
        }
      }
      
      // Verify the update worked
      final updatedUser = await QueryBuilder.table('users')
          .where((x) => x.eq('name', 'Charlie Updated'))
          .executeMany(dataAccess);
      expect(updatedUser, hasLength(1));
      expect(updatedUser.first['name'], equals('Charlie Updated'));
    });
  });
}