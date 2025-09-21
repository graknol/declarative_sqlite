import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('DbRecord API Tests', () {
    late DeclarativeDatabase db;
    
    setUp(() async {
      final schema = SchemaBuilder()
        ..table('users', (table) {
          table.text('id').notNull('');
          table.text('name').notNull('');
          table.integer('age').notNull(0);
          table.date('birth_date');
          table.text('status').lww();
          table.key(['id']).primary();
        })
        ..table('user_details_view', (table) {
          table.text('id').notNull('');
          table.text('name').notNull('');
          table.text('details').notNull('');
          table.key(['id']).primary();
        })
        ..build();
      
      db = await DeclarativeDatabase.openInMemory('test', schema: schema);
    });

    tearDown(() async {
      await db.close();
    });

    test('query() method detects CRUD vs read-only based on QueryBuilder shape', () async {
      // Insert test data
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
        'birth_date': '1993-01-01',
        'status': 'active',
      });

      // Test table query - should be CRUD-enabled
      final users = await db.query((q) => q.from('users'));
      expect(users.length, equals(1));
      expect(users.first.isCrudEnabled, isTrue);
      expect(users.first.isReadOnly, isFalse);
      expect(users.first.updateTableName, equals('users'));

      // Test view query - should be read-only
      final details = await db.query((q) => q.from('user_details_view'));
      expect(details.first.isReadOnly, isTrue);
      expect(details.first.isCrudEnabled, isFalse);
      expect(details.first.updateTableName, isNull);
    });

    test('forUpdate() enables CRUD for complex queries', () async {
      // Insert test data
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
        'birth_date': '1993-01-01',
        'status': 'active',
      });

      // Test complex query with forUpdate
      final results = await db.query(
        (q) => q.from('user_details_view').forUpdate('users')
      );
      
      expect(results.first.isCrudEnabled, isTrue);
      expect(results.first.isReadOnly, isFalse);
      expect(results.first.updateTableName, equals('users'));
    });

    test('getValue() and setValue() work correctly', () async {
      // Insert test data
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
        'birth_date': '1993-01-01',
        'status': 'active',
      });

      final users = await db.query((q) => q.from('users'));
      final user = users.first;

      // Test getValue with different types
      expect(user.getValue<String>('name'), equals('John Doe'));
      expect(user.getValue<int>('age'), equals(30));
      expect(user.getValue<DateTime>('birth_date'), isA<DateTime>());

      // Test setValue
      user.setValue('name', 'Jane Doe');
      user.setValue('age', 31);
      expect(user.getValue<String>('name'), equals('Jane Doe'));
      expect(user.getValue<int>('age'), equals(31));
    });

    test('save() only updates modified fields', () async {
      // Insert test data
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
        'birth_date': '1993-01-01',
        'status': 'active',
      });

      final users = await db.query((q) => q.from('users'));
      final user = users.first;

      // Modify only one field
      user.setValue('name', 'Jane Doe');
      await user.save();

      // Verify the change
      final updatedUsers = await db.query((q) => q.from('users'));
      final updatedUser = updatedUsers.first;
      expect(updatedUser.getValue<String>('name'), equals('Jane Doe'));
      expect(updatedUser.getValue<int>('age'), equals(30)); // Unchanged
    });

    test('reload() refreshes record data', () async {
      // Insert test data
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
        'birth_date': '1993-01-01',
        'status': 'active',
      });

      final users = await db.query((q) => q.from('users'));
      final user = users.first;

      // Modify the record directly in database
      await db.update('users', {'name': 'Updated Name'}, where: 'id = ?', whereArgs: ['user1']);

      // Reload should refresh the data
      await user.reload();
      expect(user.getValue<String>('name'), equals('Updated Name'));
    });

    test('read-only records throw errors on modification attempts', () async {
      // Insert test data  
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
        'birth_date': '1993-01-01',
        'status': 'active',
      });

      final details = await db.query((q) => q.from('user_details_view'));
      final detail = details.first;

      expect(() => detail.setValue('name', 'Test'), throwsA(isA<StateError>()));
      expect(() => detail.save(), throwsA(isA<StateError>()));
      expect(() => detail.reload(), throwsA(isA<StateError>()));
      expect(() => detail.delete(), throwsA(isA<StateError>()));
    });

    test('system column access works correctly', () async {
      // Insert test data
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
        'birth_date': '1993-01-01',
        'status': 'active',
      });

      final users = await db.query((q) => q.from('users'));
      final user = users.first;

      expect(user.systemId, isNotNull);
      expect(user.systemCreatedAt, isA<DateTime>());
      expect(user.systemVersion, isNotNull);
    });

    test('LWW columns update HLC timestamps automatically', () async {
      // Insert test data
      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
        'birth_date': '1993-01-01',
        'status': 'active',
      });

      final users = await db.query((q) => q.from('users'));
      final user = users.first;

      final originalHlc = user.getValue<String>('status__hlc');
      
      // Wait a bit to ensure different timestamp
      await Future.delayed(Duration(milliseconds: 10));
      
      // Update LWW column
      user.setValue('status', 'inactive');
      await user.save();

      final updatedUsers = await db.query((q) => q.from('users'));
      final updatedUser = updatedUsers.first;
      final newHlc = updatedUser.getValue<String>('status__hlc');

      expect(newHlc, isNot(equals(originalHlc)));
      expect(updatedUser.getValue<String>('status'), equals('inactive'));
    });
  });

  group('RecordMapFactoryRegistry Tests', () {
    test('register and use typed factory', () async {
      // This would be done at app startup
      RecordMapFactoryRegistry.register<User>(User.fromMap);

      final schema = SchemaBuilder()
        ..table('users', (table) {
          table.text('id').notNull('');
          table.text('name').notNull('');
          table.integer('age').notNull(0);
          table.key(['id']).primary();
        })
        ..build();

      final db = await DeclarativeDatabase.openInMemory('test', schema: schema);

      await db.insert('users', {
        'id': 'user1',
        'name': 'John Doe',
        'age': 30,
      });

      // Test typed query without mapper parameter
      final users = await db.queryTyped<User>((q) => q.from('users'));
      expect(users.length, equals(1));
      expect(users.first, isA<User>());
      expect(users.first.name, equals('John Doe'));
      expect(users.first.age, equals(30));

      await db.close();
    });
  });
}

// Mock User class for testing
class User extends DbRecord {
  User(Map<String, Object?> data, DeclarativeDatabase database) 
      : super(data, database);

  String get name => getTextNotNull('name');
  int get age => getIntegerNotNull('age');
  
  set name(String value) => setText('name', value);
  set age(int value) => setInteger('age', value);

  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
}