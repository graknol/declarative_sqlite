import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();

  late DeclarativeDatabase database;

  setUp(() async {
    sqfliteFfiInit();
    
    final schema = SchemaBuilder()
        .table('users', (table) {
          table.guid('id').notNull('default-id');
          table.text('name').notNull('Default Name');
          table.text('email').notNull('default@example.com');
          table.key(['id']).primary();
          table.key(['email']).unique(); // This will cause constraint violations
        })
        .build();

    database = await DeclarativeDatabase.open(
      ':memory:',
      databaseFactory: databaseFactoryFfi,
      schema: schema,
      fileRepository: FilesystemFileRepository('temp_test'),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('Bulk Load Constraint Violation Handling', () {
    test('throwException strategy throws on constraint violation', () async {
      // Insert initial data
      await database.insert('users', {
        'id': 'user-1',
        'name': 'John Doe',
        'email': 'john@example.com',
      });

      // Try to bulk load data with duplicate email (should throw)
      expect(() async {
        await database.bulkLoad(
          'users',
          [
            {
              'system_id': 'unique-server-user-1', // Different system_id to force INSERT
              'id': 'user-2',
              'name': 'Jane Doe',
              'email': 'john@example.com', // Duplicate email
            }
          ],
          onConstraintViolation: ConstraintViolationStrategy.throwException,
        );
      }, throwsException);
    });

    test('skip strategy silently skips constraint violations', () async {
      // Insert initial data
      await database.insert('users', {
        'id': 'user-1',
        'name': 'John Doe',
        'email': 'john@example.com',
      });

      // Bulk load data with duplicate email (should skip silently)
      await database.bulkLoad(
        'users',
        [
          {
            'system_id': 'unique-server-user-2', // Different system_id to force INSERT
            'id': 'user-2',
            'name': 'Jane Doe',
            'email': 'john@example.com', // Duplicate email - should be skipped
          },
          {
            'system_id': 'unique-server-user-3', // Different system_id to force INSERT
            'id': 'user-3',
            'name': 'Bob Smith',
            'email': 'bob@example.com', // Valid email - should work
          }
        ],
        onConstraintViolation: ConstraintViolationStrategy.skip,
      );

      // Verify that only the valid row was inserted
      final users = await database.queryMaps((q) => q.from('users'));
      expect(users.length, equals(2)); // Original + 1 valid new row
      
      final emails = users.map((u) => u['email']).toList();
      expect(emails, contains('john@example.com'));
      expect(emails, contains('bob@example.com'));
      expect(emails, isNot(contains('jane@example.com'))); // Jane should be skipped
    });

    test('default behavior is to throw exceptions', () async {
      // Insert initial data
      await database.insert('users', {
        'id': 'user-1',
        'name': 'John Doe',
        'email': 'john@example.com',
      });

      // Try to bulk load data with duplicate email (should throw by default)
      expect(() async {
        await database.bulkLoad('users', [
          {
            'system_id': 'unique-server-user-4', // Different system_id to force INSERT
            'id': 'user-2',
            'name': 'Jane Doe',
            'email': 'john@example.com', // Duplicate email
          }
        ]);
      }, throwsException);
    });
  });
}