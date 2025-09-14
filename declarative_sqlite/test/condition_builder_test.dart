import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

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
}