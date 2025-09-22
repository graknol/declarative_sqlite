import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Test for CRUD vs Read-only record functionality
void main() {
  late DeclarativeDatabase db;

  Schema getSchema() {
    final schemaBuilder = SchemaBuilder();
    
    // Create a table for CRUD operations
    schemaBuilder.table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.text('email').notNull('');
      table.integer('age').notNull(0);
      table.text('bio').lww();
      table.key(['id']).primary();
    });

    // Create another table for joins
    schemaBuilder.table('profiles', (table) {
      table.integer('user_id').notNull(0);
      table.text('description').notNull('');
      table.text('website');
      table.key(['user_id']).primary();
    });

    // Create a view for read-only operations
    schemaBuilder.view('user_profiles', (view) {
      view.select('users.id')
          .select('users.name')
          .select('users.email')
          .select('profiles.description')
          .select('profiles.website')
          .from('users')
          .leftJoin('profiles', 'profiles.user_id = users.id');
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

  group('CRUD vs Read-Only Record Distinction', () {
    setUp(() async {
      // Insert test data
      await db.insert('users', {
        'id': 1,
        'name': 'Alice Smith',
        'email': 'alice@example.com',
        'age': 30,
        'bio': 'Software engineer',
      });

      await db.insert('profiles', {
        'user_id': 1,
        'description': 'Passionate developer',
        'website': 'https://alice.dev',
      });
    });

    test('table queries return CRUD-enabled records', () async {
      final users = await db.queryTableRecords('users');
      
      expect(users.length, 1);
      final user = users.first;
      
      expect(user.isReadOnly, false);
      expect(user.isCrudEnabled, true);
      expect(user.updateTableName, 'users');
      
      // Should be able to modify
      user.setValue('name', 'Alice Johnson');
      expect(user.getValue<String>('name'), 'Alice Johnson');
      
      // Should be able to save
      await user.save();
      
      // Verify the change persisted
      final updatedUsers = await db.queryTableRecords('users', where: 'id = 1');
      expect(updatedUsers.first.getValue<String>('name'), 'Alice Johnson');
    });

    test('view queries return read-only records by default', () async {
      final userProfiles = await db.queryTableRecords('user_profiles');
      
      expect(userProfiles.length, 1);
      final userProfile = userProfiles.first;
      
      expect(userProfile.isReadOnly, true);
      expect(userProfile.isCrudEnabled, false);
      expect(userProfile.updateTableName, null);
      
      // Should not be able to modify
      expect(
        () => userProfile.setValue('name', 'Modified Name'),
        throwsStateError,
      );
      
      // Should not be able to save
      expect(() => userProfile.save(), throwsStateError);
      
      // Should not be able to delete
      expect(() => userProfile.delete(), throwsStateError);
      
      // Should not be able to reload
      expect(() => userProfile.reload(), throwsStateError);
    });

    test('queries with forUpdate return CRUD-enabled records', () async {
      final userProfiles = await db.queryRecords(
        (q) => q.from('user_profiles').forUpdate('users'),
      );
      
      expect(userProfiles.length, 1);
      final userProfile = userProfiles.first;
      
      expect(userProfile.isReadOnly, false);
      expect(userProfile.isCrudEnabled, true);
      expect(userProfile.updateTableName, 'users');
      
      // Should be able to modify columns that exist in the target table
      userProfile.setValue('name', 'Alice Modified');
      userProfile.setValue('email', 'alice.modified@example.com');
      
      // Should be able to save
      await userProfile.save();
      
      // Verify changes persisted in the target table
      final updatedUsers = await db.queryTableRecords('users', where: 'id = 1');
      final updatedUser = updatedUsers.first;
      expect(updatedUser.getValue<String>('name'), 'Alice Modified');
      expect(updatedUser.getValue<String>('email'), 'alice.modified@example.com');
    });

    test('forUpdate validates target table exists', () async {
      expect(
        () => db.queryRecords((q) => q.from('users').forUpdate('nonexistent_table')),
        throwsArgumentError,
      );
    });

    test('forUpdate validates system_id presence', () async {
      // Create a query that doesn't include system_id
      expect(
        () => db.queryRecords(
          (q) => q.from('users').select('name').select('email').forUpdate('users'),
        ),
        throwsStateError,
      );
    });

    test('forUpdate validates system_version presence', () async {
      // Create a query that includes system_id but not system_version
      expect(
        () => db.queryRecords(
          (q) => q.from('users').select('system_id').select('name').forUpdate('users'),
        ),
        throwsStateError,
      );
    });
  });

  group('Reload Functionality', () {
    test('reload updates record with fresh data from database', () async {
      final users = await db.queryTableRecords('users');
      final user = users.first;
      
      final originalName = user.getValue<String>('name');
      
      // Modify the record in memory
      user.setValue('name', 'Modified Name');
      expect(user.getValue<String>('name'), 'Modified Name');
      expect(user.modifiedFields, contains('name'));
      
      // Reload should refresh data and clear modifications
      await user.reload();
      
      expect(user.getValue<String>('name'), originalName);
      expect(user.modifiedFields.isEmpty, true);
    });

    test('reload fails for read-only records', () async {
      final userProfiles = await db.queryTableRecords('user_profiles');
      final userProfile = userProfiles.first;
      
      expect(() => userProfile.reload(), throwsStateError);
    });

    test('reload fails for records without system_id', () async {
      final record = RecordFactory.fromTable({
        'name': 'Test User',
        'email': 'test@example.com',
      }, 'users', db);
      
      expect(() => record.reload(), throwsStateError);
    });

    test('reload fails if record no longer exists', () async {
      final users = await db.queryTableRecords('users');
      final user = users.first;
      
      // Delete the record from the database
      await db.delete('users', where: 'id = ?', whereArgs: [1]);
      
      // Reload should fail
      expect(() => user.reload(), throwsStateError);
    });
  });

  group('Complex Query Scenarios', () {
    test('join query with forUpdate allows updates to target table', () async {
      // Complex join query with forUpdate
      final results = await db.queryRecords(
        (q) => q.from('users')
            .select('users.system_id')
            .select('users.system_version') 
            .select('users.name')
            .select('users.email')
            .select('profiles.description as profile_description')
            .leftJoin('profiles', 'profiles.user_id = users.id')
            .forUpdate('users'),
      );
      
      expect(results.length, 1);
      final result = results.first;
      
      expect(result.isCrudEnabled, true);
      expect(result.updateTableName, 'users');
      
      // Can modify columns from the target table
      result.setValue('name', 'Alice Updated');
      result.setValue('email', 'alice.updated@example.com');
      
      await result.save();
      
      // Verify update in the target table
      final updatedUsers = await db.queryTableRecords('users');
      final updatedUser = updatedUsers.first;
      expect(updatedUser.getValue<String>('name'), 'Alice Updated');
      expect(updatedUser.getValue<String>('email'), 'alice.updated@example.com');
    });

    test('attempting to modify non-target table columns fails validation', () async {
      final results = await db.queryRecords(
        (q) => q.from('users')
            .select('users.system_id')
            .select('users.system_version')
            .select('users.name')
            .select('profiles.description')
            .leftJoin('profiles', 'profiles.user_id = users.id')
            .forUpdate('users'),
      );
      
      final result = results.first;
      
      // Can modify users table columns
      result.setValue('name', 'Alice Modified');
      
      // Cannot modify profiles table columns when forUpdate targets users
      expect(
        () => result.setValue('description', 'Modified Description'),
        throwsArgumentError,
      );
    });

    test('streaming queries respect CRUD vs read-only distinction', () async {
      final tableStream = db.streamRecords((q) => q.from('users'));
      final viewStream = db.streamRecords((q) => q.from('user_profiles'));
      final forUpdateStream = db.streamRecords(
        (q) => q.from('user_profiles').forUpdate('users'),
      );
      
      // Table stream should return CRUD-enabled records
      final tableResults = await tableStream.first;
      expect(tableResults.first.isCrudEnabled, true);
      
      // View stream should return read-only records
      final viewResults = await viewStream.first;
      expect(viewResults.first.isReadOnly, true);
      
      // ForUpdate stream should return CRUD-enabled records
      final forUpdateResults = await forUpdateStream.first;
      expect(forUpdateResults.first.isCrudEnabled, true);
    });
  });

  group('Error Handling', () {
    test('helpful error messages for read-only operations', () async {
      final userProfiles = await db.queryTableRecords('user_profiles');
      final userProfile = userProfiles.first;
      
      expect(
        () => userProfile.setValue('name', 'Test'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot modify read-only record'),
        )),
      );
      
      expect(
        () => userProfile.save(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot save read-only record'),
        )),
      );
    });

    test('helpful error messages for missing system columns', () async {
      expect(
        () => db.queryRecords(
          (q) => q.from('users').select('name').forUpdate('users'),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('must include system_id column'),
        )),
      );
    });
  });
}