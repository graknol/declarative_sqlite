import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Integration test demonstrating the complete DbRecord workflow
void main() {
  late DeclarativeDatabase db;

  Schema getSchema() {
    final schemaBuilder = SchemaBuilder();
    schemaBuilder.table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.text('email').notNull('');
      table.integer('age').notNull(0);
      table.date('birth_date');
      table.text('bio').lww(); // LWW column
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

  test('Complete DbRecord workflow integration test', () async {
    // === Step 1: Insert initial data using traditional Map API ===
    await db.insert('users', {
      'id': 1,
      'name': 'Alice Smith',
      'email': 'alice@example.com',
      'age': 30,
      'birth_date': DateTime(1993, 5, 15).toIso8601String(),
      'bio': 'Software engineer',
    });

    await db.insert('users', {
      'id': 2,
      'name': 'Bob Johnson',
      'email': 'bob@example.com',
      'age': 28,
      'birth_date': DateTime(1995, 8, 20).toIso8601String(),
      'bio': 'Designer',
    });

    // === Step 2: Query using DbRecord API ===
    final users = await db.queryRecords(
      (q) => q.from('users').where(col('age').gte(25)).orderBy(['name']),
    );

    expect(users.length, 2);
    expect(users[0].getValue<String>('name'), 'Alice Smith');
    expect(users[1].getValue<String>('name'), 'Bob Johnson');

    // === Step 3: Verify typed getters work correctly ===
    final alice = users[0];
    expect(alice.getValue<String>('name'), 'Alice Smith');
    expect(alice.getValue<String>('email'), 'alice@example.com');
    expect(alice.getValue<int>('age'), 30);
    
    // Test DateTime conversion
    final birthDate = alice.getValue<DateTime>('birth_date');
    expect(birthDate?.year, 1993);
    expect(birthDate?.month, 5);
    expect(birthDate?.day, 15);

    // Test system columns
    expect(alice.systemId, isNotNull);
    expect(alice.systemCreatedAt, isA<DateTime>());
    expect(alice.systemVersion, isNotNull);

    // === Step 4: Test typed setters and modification tracking ===
    expect(alice.modifiedFields.isEmpty, true);

    alice.setValue('age', 31);
    alice.setValue('email', 'alice.smith@example.com');
    alice.setValue('birth_date', DateTime(1993, 5, 16)); // Corrected date

    expect(alice.modifiedFields, containsAll(['age', 'email', 'birth_date']));
    expect(alice.getValue<int>('age'), 31);
    expect(alice.getValue<String>('email'), 'alice.smith@example.com');

    // === Step 5: Test LWW column handling ===
    final originalBioHlc = alice.getRawValue('bio__hlc');
    expect(originalBioHlc, isNotNull);

    // Small delay to ensure different HLC
    await Future.delayed(Duration(milliseconds: 1));

    alice.setValue('bio', 'Senior Software Engineer');
    
    expect(alice.modifiedFields, contains('bio'));
    expect(alice.modifiedFields, contains('bio__hlc'));
    
    final newBioHlc = alice.getRawValue('bio__hlc');
    expect(newBioHlc, isNotNull);
    expect(newBioHlc, isNot(equals(originalBioHlc)));

    // === Step 6: Save changes and verify persistence ===
    await alice.save();
    expect(alice.modifiedFields.isEmpty, true);

    // Verify changes were persisted
    final updatedUsers = await db.queryTableRecords('users', where: 'id = 1');
    final updatedAlice = updatedUsers.first;

    expect(updatedAlice.getValue<int>('age'), 31);
    expect(updatedAlice.getValue<String>('email'), 'alice.smith@example.com');
    expect(updatedAlice.getValue<String>('bio'), 'Senior Software Engineer');
    
    final updatedBirthDate = updatedAlice.getValue<DateTime>('birth_date');
    expect(updatedBirthDate?.day, 16);

    // === Step 7: Test queryTableRecords method ===
    final bobUsers = await db.queryTableRecords(
      'users',
      where: 'name = ?',
      whereArgs: ['Bob Johnson'],
    );

    expect(bobUsers.length, 1);
    final bob = bobUsers.first;
    expect(bob.getValue<String>('email'), 'bob@example.com');
    expect(bob.getValue<int>('age'), 28);

    // === Step 8: Test record deletion ===
    await bob.delete();

    final remainingUsers = await db.queryTableRecords('users');
    expect(remainingUsers.length, 1);
    expect(remainingUsers.first.getValue<String>('name'), 'Alice Smith');

    // === Step 9: Test creating new record with DbRecord ===
    final newUser = RecordFactory.fromMap({
      'id': 3,
      'name': 'Charlie Brown',
      'email': 'charlie@example.com',
      'age': 35,
      'birth_date': DateTime(1988, 12, 25).toIso8601String(),
      'bio': 'Product Manager',
    }, 'users', db);

    await newUser.insert();

    final allUsers = await db.queryTableRecords('users');
    expect(allUsers.length, 2);
    
    final charlie = allUsers.firstWhere(
      (user) => user.getValue<String>('name') == 'Charlie Brown',
    );
    expect(charlie.getValue<int>('age'), 35);
    expect(charlie.systemId, isNotNull);

    // === Step 10: Test error handling ===
    expect(
      () => alice.getValue('nonexistent_column'),
      throwsArgumentError,
    );

    // Test save without system_id
    final orphanUser = RecordFactory.fromMap({'name': 'Orphan'}, 'users', db);
    expect(() => orphanUser.save(), throwsStateError);
    expect(() => orphanUser.delete(), throwsStateError);

    // === Step 11: Verify backward compatibility ===
    // The old Map API should still work alongside the new DbRecord API
    final mapResults = await db.queryTable('users');
    expect(mapResults.length, 2);
    expect(mapResults[0]['name'], isA<String>());

    final recordResults = await db.queryTableRecords('users');
    expect(recordResults.length, 2);
    expect(recordResults[0].getValue<String>('name'), isA<String>());
  });

  test('DbRecord streaming integration', () async {
    // Insert initial data
    await db.insert('users', {
      'id': 1,
      'name': 'User 1',
      'email': 'user1@example.com',
      'age': 25,
    });

    // Create streaming query
    final userStream = db.streamRecords(
      (q) => q.from('users').where(col('age').gte(20)),
    );

    var emissionCount = 0;
    final subscription = userStream.listen((users) {
      emissionCount++;
      
      if (emissionCount == 1) {
        // Initial emission
        expect(users.length, 1);
        expect(users[0].getValue<String>('name'), 'User 1');
      } else if (emissionCount == 2) {
        // After insert
        expect(users.length, 2);
        final names = users.map((u) => u.getValue<String>('name')).toList();
        expect(names, containsAll(['User 1', 'User 2']));
      }
    });

    // Wait for initial emission
    await Future.delayed(Duration(milliseconds: 10));

    // Insert another user to trigger stream update
    await db.insert('users', {
      'id': 2,
      'name': 'User 2',
      'email': 'user2@example.com',
      'age': 30,
    });

    // Wait for stream update
    await Future.delayed(Duration(milliseconds: 10));

    expect(emissionCount, 2);
    await subscription.cancel();
  });
}