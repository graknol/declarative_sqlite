import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Test for the enhanced DbRecord features:
/// - Singleton HLC clock
/// - RecordMapFactoryRegistry
/// - Typed query methods
void main() {
  late DeclarativeDatabase db;

  // Mock generated User class for testing
  class User extends DbRecord {
    User(Map<String, Object?> data, DeclarativeDatabase database)
        : super(data, 'users', database);

    // Typed getters
    int get id => getIntegerNotNull('id');
    String get name => getTextNotNull('name');
    String get email => getTextNotNull('email');
    int get age => getIntegerNotNull('age');
    DateTime? get birthDate => getDateTime('birth_date');
    String? get bio => getText('bio');

    // Typed setters
    set id(int value) => setInteger('id', value);
    set name(String value) => setText('name', value);
    set email(String value) => setText('email', value);
    set age(int value) => setInteger('age', value);
    set birthDate(DateTime? value) => setDateTime('birth_date', value);
    set bio(String? value) => setText('bio', value);

    // Factory for registry
    static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
      return User(data, database);
    }
  }

  Schema getSchema() {
    final schemaBuilder = SchemaBuilder();
    schemaBuilder.table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.text('email').notNull('');
      table.integer('age').notNull(0);
      table.date('birth_date');
      table.text('bio').lww();
      table.key(['id']).primary();
    });
    return schemaBuilder.build();
  }

  setUpAll(() async {
    db = await setupTestDatabase(schema: getSchema());
  });

  setUp(() async {
    await clearDatabase(db.db);
    RecordMapFactoryRegistry.clear(); // Clear registry before each test
    HlcClock.resetInstance(); // Reset singleton for testing
  });

  tearDownAll(() async {
    await db.close();
  });

  group('HLC Clock Singleton', () {
    test('HLC clock is singleton across multiple instances', () {
      final clock1 = HlcClock();
      final clock2 = HlcClock();
      
      expect(identical(clock1, clock2), true);
      expect(clock1.nodeId, clock2.nodeId);
    });

    test('HLC clock preserves node ID on subsequent calls', () {
      final clock1 = HlcClock(nodeId: 'test-node-123');
      final clock2 = HlcClock(nodeId: 'different-node'); // Should be ignored
      
      expect(identical(clock1, clock2), true);
      expect(clock1.nodeId, 'test-node-123');
      expect(clock2.nodeId, 'test-node-123'); // Same as first
    });

    test('HLC clock instance property works', () {
      // Should throw before creation
      expect(() => HlcClock.instance, throwsStateError);
      
      final clock = HlcClock();
      expect(identical(clock, HlcClock.instance), true);
    });

    test('HLC clock reset works for testing', () {
      final clock1 = HlcClock(nodeId: 'first');
      expect(clock1.nodeId, 'first');
      
      HlcClock.resetInstance();
      
      final clock2 = HlcClock(nodeId: 'second');
      expect(clock2.nodeId, 'second');
      expect(identical(clock1, clock2), false);
    });
  });

  group('RecordMapFactoryRegistry', () {
    test('can register and retrieve factories', () {
      expect(RecordMapFactoryRegistry.hasFactory<User>(), false);
      
      RecordMapFactoryRegistry.register<User>((data) => User.fromMap(data, db));
      
      expect(RecordMapFactoryRegistry.hasFactory<User>(), true);
      expect(RecordMapFactoryRegistry.registeredTypes, contains(User));
    });

    test('throws error when factory not registered', () {
      expect(
        () => RecordMapFactoryRegistry.getFactory<User>(),
        throwsArgumentError,
      );
    });

    test('can create instances using registered factory', () {
      RecordMapFactoryRegistry.register<User>((data) => User.fromMap(data, db));
      
      final userData = {
        'id': 1,
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 25,
      };
      
      final user = RecordMapFactoryRegistry.create<User>(userData);
      expect(user, isA<User>());
      expect(user.name, 'Test User');
      expect(user.age, 25);
    });

    test('clear() removes all registrations', () {
      RecordMapFactoryRegistry.register<User>((data) => User.fromMap(data, db));
      expect(RecordMapFactoryRegistry.hasFactory<User>(), true);
      
      RecordMapFactoryRegistry.clear();
      expect(RecordMapFactoryRegistry.hasFactory<User>(), false);
      expect(RecordMapFactoryRegistry.registeredTypes.isEmpty, true);
    });
  });

  group('Generated Class Typed Access', () {
    late User user;
    
    setUp(() async {
      await db.insert('users', {
        'id': 1,
        'name': 'Alice Smith',
        'email': 'alice@example.com',
        'age': 30,
        'birth_date': DateTime(1993, 5, 15).toIso8601String(),
        'bio': 'Software engineer',
      });
      
      final records = await db.queryTableRecords('users');
      user = User(records.first.data, db);
    });

    test('typed getters work correctly', () {
      expect(user.id, 1);
      expect(user.name, 'Alice Smith');
      expect(user.email, 'alice@example.com');
      expect(user.age, 30);
      expect(user.birthDate?.year, 1993);
      expect(user.birthDate?.month, 5);
      expect(user.birthDate?.day, 15);
      expect(user.bio, 'Software engineer');
    });

    test('typed setters work correctly', () {
      expect(user.modifiedFields.isEmpty, true);
      
      user.name = 'Alice Johnson';
      user.age = 31;
      user.birthDate = DateTime(1993, 5, 16);
      
      expect(user.modifiedFields, containsAll(['name', 'age', 'birth_date']));
      expect(user.name, 'Alice Johnson');
      expect(user.age, 31);
      expect(user.birthDate?.day, 16);
    });

    test('LWW column setter updates HLC', () async {
      final originalHlc = user.getRawValue('bio__hlc');
      
      // Small delay to ensure different HLC
      await Future.delayed(Duration(milliseconds: 1));
      
      user.bio = 'Senior Software Engineer';
      
      expect(user.modifiedFields, contains('bio'));
      expect(user.modifiedFields, contains('bio__hlc'));
      
      final newHlc = user.getRawValue('bio__hlc');
      expect(newHlc, isNot(equals(originalHlc)));
    });

    test('save and persistence works with typed setters', () async {
      user.name = 'Updated Name';
      user.age = 32;
      await user.save();
      
      expect(user.modifiedFields.isEmpty, true);
      
      // Verify persistence
      final updatedRecords = await db.queryTableRecords('users', where: 'id = 1');
      final updatedUser = User(updatedRecords.first.data, db);
      
      expect(updatedUser.name, 'Updated Name');
      expect(updatedUser.age, 32);
    });
  });

  group('Typed Query Methods', () {
    setUp(() async {
      // Register factory
      RecordMapFactoryRegistry.register<User>((data) => User.fromMap(data, db));
      
      // Insert test data
      await db.insert('users', {
        'id': 1,
        'name': 'User 1',
        'email': 'user1@example.com',
        'age': 25,
      });
      await db.insert('users', {
        'id': 2,
        'name': 'User 2',
        'email': 'user2@example.com',
        'age': 30,
      });
    });

    test('queryTyped returns typed objects', () async {
      final users = await db.queryTyped<User>(
        (q) => q.from('users').where(col('age').gte(25)).orderBy(['name']),
      );
      
      expect(users.length, 2);
      expect(users[0], isA<User>());
      expect(users[0].name, 'User 1');
      expect(users[1].name, 'User 2');
      
      // Test direct property access
      expect(users[0].age, 25);
      expect(users[1].age, 30);
    });

    test('queryTableTyped returns typed objects', () async {
      final users = await db.queryTableTyped<User>(
        'users',
        where: 'age = ?',
        whereArgs: [30],
      );
      
      expect(users.length, 1);
      expect(users[0], isA<User>());
      expect(users[0].name, 'User 2');
      expect(users[0].age, 30);
    });

    test('queryTyped throws error when factory not registered', () async {
      RecordMapFactoryRegistry.clear();
      
      expect(
        () => db.queryTyped<User>((q) => q.from('users')),
        throwsArgumentError,
      );
    });

    test('streamTyped returns typed objects', () async {
      final userStream = db.streamTyped<User>((q) => q.from('users'));
      
      final users = await userStream.first;
      expect(users.length, 2);
      expect(users[0], isA<User>());
      expect(users[0].name, 'User 1');
    });

    test('typed queries work with property modifications', () async {
      final users = await db.queryTyped<User>((q) => q.from('users'));
      final user = users.first;
      
      // Modify using property setters
      user.age = 99;
      user.email = 'updated@example.com';
      await user.save();
      
      // Query again and verify
      final updatedUsers = await db.queryTyped<User>(
        (q) => q.from('users').where(col('id').eq(user.id)),
      );
      final updatedUser = updatedUsers.first;
      
      expect(updatedUser.age, 99);
      expect(updatedUser.email, 'updated@example.com');
    });
  });

  group('Helper Methods', () {
    late DbRecord record;
    
    setUp(() async {
      await db.insert('users', {
        'id': 1,
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 25,
        'birth_date': DateTime(1998, 1, 1).toIso8601String(),
      });
      
      final records = await db.queryTableRecords('users');
      record = records.first;
    });

    test('typed helper getters work', () {
      expect(record.getText('name'), 'Test User');
      expect(record.getTextNotNull('name'), 'Test User');
      expect(record.getInteger('age'), 25);
      expect(record.getIntegerNotNull('age'), 25);
      expect(record.getDateTime('birth_date')?.year, 1998);
      expect(record.getDateTimeNotNull('birth_date').year, 1998);
    });

    test('non-null helpers throw when value is null', () {
      expect(() => record.getTextNotNull('bio'), throwsStateError);
      expect(() => record.getDateTimeNotNull('bio'), throwsStateError);
    });

    test('typed helper setters work', () {
      record.setText('name', 'New Name');
      record.setInteger('age', 26);
      record.setDateTime('birth_date', DateTime(1999, 1, 1));
      
      expect(record.getText('name'), 'New Name');
      expect(record.getInteger('age'), 26);
      expect(record.getDateTime('birth_date')?.year, 1999);
      expect(record.modifiedFields, containsAll(['name', 'age', 'birth_date']));
    });
  });
}