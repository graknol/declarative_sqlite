import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Test suite for DynamicRecord and ergonomic property access
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
          .text('full_name', (col) => col.notNull())
          .text('email_address', (col) => col.unique())
          .integer('age')
          .real('salary')
          .text('created_at')
          .integer('is_active', (col) => col.withDefaultValue(1)));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);

    // Insert test data
    await dataAccess.insert('users', {
      'full_name': 'Alice Smith',
      'email_address': 'alice@example.com',
      'age': 30,
      'salary': 75000.5,
      'created_at': '2023-01-15T10:30:00Z',
      'is_active': 1,
    });

    await dataAccess.insert('users', {
      'full_name': 'Bob Johnson',
      'email_address': 'bob@example.com',
      'age': 25,
      'salary': 65000.0,
      'created_at': '2023-02-20T14:15:00Z',
      'is_active': 0,
    });
  });

  tearDown(() async {
    await database.close();
  });

  group('DynamicRecord Property Access Tests', () {
    test('should access columns as properties', () async {
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('full_name', 'Alice Smith'));

      final result = await query.executeDynamicSingle(dataAccess);
      
      expect(result, isNotNull);
      
      // Test direct property access
      expect((result as dynamic).full_name, 'Alice Smith');
      expect((result as dynamic).email_address, 'alice@example.com');
      expect((result as dynamic).age, 30);
      expect((result as dynamic).salary, 75000.5);
      expect((result as dynamic).is_active, 1);
    });

    test('should support typed getters', () async {
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('full_name', 'Alice Smith'));

      final result = await query.executeDynamicSingle(dataAccess);
      
      expect(result, isNotNull);
      
      // Test typed getters
      expect((result as dynamic).getStringFullName, 'Alice Smith');
      expect((result as dynamic).getStringEmailAddress, 'alice@example.com');
      expect((result as dynamic).getIntAge, 30);
      expect((result as dynamic).getDoubleSalary, 75000.5);
      expect((result as dynamic).getBoolIsActive, true);
      
      // Test date parsing
      final createdAt = (result as dynamic).getDateCreatedAt as DateTime?;
      expect(createdAt, isNotNull);
      expect(createdAt!.year, 2023);
      expect(createdAt.month, 1);
      expect(createdAt.day, 15);
    });

    test('should work with camelCase access for snake_case columns', () async {
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('full_name', 'Alice Smith'));

      final result = await query.executeDynamicSingle(dataAccess);
      
      expect(result, isNotNull);
      
      // Test camelCase access for snake_case columns
      expect((result as dynamic).fullName, 'Alice Smith');
      expect((result as dynamic).emailAddress, 'alice@example.com');
      expect((result as dynamic).isActive, 1);
    });

    test('should return multiple DynamicRecord instances', () async {
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .orderByColumn('age');

      final results = await query.executeDynamicMany(dataAccess);
      
      expect(results, hasLength(2));
      
      // Test first result (Bob - age 25)
      expect((results[0] as dynamic).full_name, 'Bob Johnson');
      expect((results[0] as dynamic).age, 25);
      
      // Test second result (Alice - age 30)
      expect((results[1] as dynamic).full_name, 'Alice Smith');
      expect((results[1] as dynamic).age, 30);
    });

    test('should maintain compatibility with index operator', () async {
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('full_name', 'Alice Smith'));

      final result = await query.executeDynamicSingle(dataAccess);
      
      expect(result, isNotNull);
      
      // Test that index operator still works
      expect(result!['full_name'], 'Alice Smith');
      expect(result['email_address'], 'alice@example.com');
      expect(result['age'], 30);
      
      // Test utility methods
      expect(result.containsKey('full_name'), true);
      expect(result.containsKey('nonexistent'), false);
      expect(result.columnNames, contains('full_name'));
      expect(result.columnNames, contains('email_address'));
    });

    test('should handle non-existent properties gracefully', () async {
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('full_name', 'Alice Smith'));

      final result = await query.executeDynamicSingle(dataAccess);
      
      expect(result, isNotNull);
      
      // Test that accessing non-existent property throws
      expect(() => (result as dynamic).nonExistentColumn, throwsA(isA<NoSuchMethodError>()));
    });
  });

  group('Interface-like Usage Pattern Tests', () {
    test('should work with developer-defined interface pattern', () async {
      // This demonstrates the pattern the user was asking about
      final query = QueryBuilder()
          .selectAll()
          .from('users')
          .where(ConditionBuilder.eq('full_name', 'Alice Smith'));

      final result = await query.executeDynamicSingle(dataAccess);
      
      expect(result, isNotNull);
      
      // Developer can now write code as if they have an interface:
      // interface UserRecord {
      //   String get full_name;
      //   String get email_address;
      //   int get age;
      //   double get salary;
      // }
      
      final user = result as dynamic;
      
      // This looks like interface access but is actually noSuchMethod
      String name = user.full_name;
      String email = user.email_address;
      int age = user.age;
      double salary = user.salary;
      
      expect(name, 'Alice Smith');
      expect(email, 'alice@example.com');
      expect(age, 30);
      expect(salary, 75000.5);
    });
  });
}