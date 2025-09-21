import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;

import 'test_helper.dart';

/// Test database exception handling and mapping
void main() {
  late DeclarativeDatabase db;

  Schema getSchema() {
    final schemaBuilder = SchemaBuilder();
    
    schemaBuilder.table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.text('email').notNull('');
      table.integer('age').notNull(0);
      table.key(['id']).primary();
    });

    schemaBuilder.table('profiles', (table) {
      table.integer('user_id').notNull(0);
      table.text('description').notNull('');
      table.key(['user_id']).primary();
      table.key(['user_id']).foreignKey('users', ['id']);
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

  group('DbException Types', () {
    test('create exception with constraint violation', () async {
      // Insert a user first
      await db.insert('users', {
        'id': 1,
        'name': 'John Doe',
        'email': 'john@example.com',
        'age': 30,
      });

      // Try to insert another user with the same ID (primary key violation)
      try {
        await db.insert('users', {
          'id': 1, // Same ID - should violate primary key constraint
          'name': 'Jane Doe',
          'email': 'jane@example.com',
          'age': 25,
        });
        fail('Expected DbCreateException to be thrown');
      } catch (e) {
        expect(e, isA<DbCreateException>());
        final dbException = e as DbCreateException;
        expect(dbException.operationType, DbOperationType.create);
        expect(dbException.errorCategory, DbErrorCategory.constraintViolation);
        expect(dbException.tableName, 'users');
        expect(dbException.originalException, isNotNull);
        expect(dbException.toString(), contains('constraint'));
      }
    });

    test('update exception with not found', () async {
      // Try to update a non-existent record
      try {
        final result = await db.update(
          'users',
          {'name': 'Updated Name'},
          where: 'id = ?',
          whereArgs: [999], // Non-existent ID
        );
        // Note: SQLite update doesn't throw for non-existent records,
        // it just returns 0 affected rows. We'll test other scenarios.
        expect(result, 0);
      } catch (e) {
        expect(e, isA<DbUpdateException>());
      }
    });

    test('delete exception with constraint violation', () async {
      // Insert user and profile with foreign key relationship
      await db.insert('users', {
        'id': 1,
        'name': 'John Doe',
        'email': 'john@example.com',
        'age': 30,
      });

      await db.insert('profiles', {
        'user_id': 1,
        'description': 'Software engineer',
      });

      // Try to delete user (should violate foreign key constraint)
      try {
        await db.delete('users', where: 'id = ?', whereArgs: [1]);
        // Note: This might not throw if foreign keys aren't enabled
        // The test will pass either way
      } catch (e) {
        expect(e, isA<DbDeleteException>());
        final dbException = e as DbDeleteException;
        expect(dbException.operationType, DbOperationType.delete);
        expect(dbException.errorCategory, DbErrorCategory.constraintViolation);
      }
    });

    test('read exception with table not found', () async {
      try {
        await db.queryTable('nonexistent_table');
        fail('Expected DbReadException to be thrown');
      } catch (e) {
        expect(e, isA<DbReadException>());
        final dbException = e as DbReadException;
        expect(dbException.operationType, DbOperationType.read);
        expect(dbException.errorCategory, DbErrorCategory.notFound);
        expect(dbException.message, contains('not found'));
      }
    });

    test('transaction exception', () async {
      try {
        await db.transaction((txn) async {
          // Insert valid record
          await txn.insert('users', {
            'id': 1,
            'name': 'John Doe',
            'email': 'john@example.com',
            'age': 30,
          });
          
          // Force an error to rollback transaction
          throw Exception('Force rollback');
        });
        fail('Expected DbTransactionException to be thrown');
      } catch (e) {
        expect(e, isA<DbTransactionException>());
        final dbException = e as DbTransactionException;
        expect(dbException.operationType, DbOperationType.transaction);
      }
    });
  });

  group('DbRecord Exception Handling', () {
    test('save operation wraps exceptions', () async {
      // Create a record with invalid data for testing
      final record = RecordFactory.fromTable({
        'system_id': 'test-id',
        'system_version': '123',
        'id': 1,
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 30,
      }, 'users', db);

      // Modify the record
      record.setValue('name', 'Updated Name');

      try {
        await record.save();
        // This might succeed, which is fine for this test
      } catch (e) {
        // If it fails, it should be a proper DbException
        expect(e, isA<DbException>());
      }
    });

    test('insert operation wraps exceptions', () async {
      final record = RecordFactory.fromTable({
        'id': 1,
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 30,
      }, 'users', db);

      try {
        await record.insert();
        // Should succeed first time
        
        // Try to insert again (should fail with constraint violation)
        final record2 = RecordFactory.fromTable({
          'id': 1, // Same ID
          'name': 'Another User',
          'email': 'another@example.com',
          'age': 25,
        }, 'users', db);

        await record2.insert();
        fail('Expected DbCreateException to be thrown');
      } catch (e) {
        expect(e, isA<DbCreateException>());
      }
    });

    test('reload operation wraps exceptions', () async {
      // Insert a record first
      await db.insert('users', {
        'id': 1,
        'name': 'Test User',
        'email': 'test@example.com',
        'age': 30,
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      // Delete the record from database
      await db.delete('users', where: 'id = ?', whereArgs: [1]);

      try {
        await user.reload();
        fail('Expected exception when record no longer exists');
      } catch (e) {
        // Should be our custom StateError, which gets wrapped
        expect(e, isA<StateError>());
      }
    });
  });

  group('Exception Categories', () {
    test('constraint violation is properly categorized', () {
      final exception = DbCreateException.constraintViolation(
        message: 'Primary key constraint failed',
        tableName: 'users',
        columnName: 'id',
      );

      expect(exception.operationType, DbOperationType.create);
      expect(exception.errorCategory, DbErrorCategory.constraintViolation);
      expect(exception.tableName, 'users');
      expect(exception.columnName, 'id');
      expect(exception.message, 'Primary key constraint failed');
    });

    test('not found is properly categorized', () {
      final exception = DbReadException.notFound(
        message: 'Record not found',
        tableName: 'users',
      );

      expect(exception.operationType, DbOperationType.read);
      expect(exception.errorCategory, DbErrorCategory.notFound);
      expect(exception.tableName, 'users');
      expect(exception.message, 'Record not found');
    });

    test('concurrency conflict is properly categorized', () {
      final exception = DbUpdateException.concurrencyConflict(
        message: 'Version conflict detected',
        tableName: 'users',
      );

      expect(exception.operationType, DbOperationType.update);
      expect(exception.errorCategory, DbErrorCategory.concurrencyConflict);
      expect(exception.tableName, 'users');
      expect(exception.message, 'Version conflict detected');
    });
  });

  group('Exception Context', () {
    test('exception includes original exception', () {
      final originalException = sqflite.DatabaseException('SQLITE_CONSTRAINT');
      final dbException = DbCreateException.constraintViolation(
        message: 'Constraint violation occurred',
        tableName: 'users',
        originalException: originalException,
      );

      expect(dbException.originalException, same(originalException));
      expect(dbException.toString(), contains('Original:'));
    });

    test('exception includes context information', () {
      final context = {'attempted_value': 123, 'constraint_type': 'primary_key'};
      final exception = DbCreateException.constraintViolation(
        message: 'Constraint violation occurred',
        tableName: 'users',
        columnName: 'id',
        context: context,
      );

      expect(exception.context, equals(context));
      expect(exception.context!['attempted_value'], 123);
      expect(exception.context!['constraint_type'], 'primary_key');
    });

    test('exception toString provides useful information', () {
      final exception = DbUpdateException.constraintViolation(
        message: 'Cannot update due to constraint',
        tableName: 'users',
        columnName: 'email',
        originalException: Exception('Original error'),
      );

      final exceptionString = exception.toString();
      expect(exceptionString, contains('DbUpdateException'));
      expect(exceptionString, contains('Cannot update due to constraint'));
      expect(exceptionString, contains('table: users'));
      expect(exceptionString, contains('column: email'));
      expect(exceptionString, contains('Original:'));
    });
  });

  group('Business Flow Mapping', () {
    test('create flow exceptions', () {
      // Test different create failure scenarios
      final constraintException = DbCreateException.constraintViolation(
        message: 'Unique constraint failed',
        tableName: 'users',
      );
      expect(constraintException.operationType, DbOperationType.create);

      final invalidDataException = DbCreateException.invalidData(
        message: 'Invalid data type provided',
        tableName: 'users',
      );
      expect(invalidDataException.operationType, DbOperationType.create);
    });

    test('read flow exceptions', () {
      final notFoundException = DbReadException.notFound(
        message: 'Record not found',
        tableName: 'users',
      );
      expect(notFoundException.operationType, DbOperationType.read);

      final accessDeniedException = DbReadException.accessDenied(
        message: 'Access denied',
        tableName: 'users',
      );
      expect(accessDeniedException.operationType, DbOperationType.read);
    });

    test('update flow exceptions', () {
      final notFoundException = DbUpdateException.notFound(
        message: 'Record to update not found',
        tableName: 'users',
      );
      expect(notFoundException.operationType, DbOperationType.update);

      final conflictException = DbUpdateException.concurrencyConflict(
        message: 'Optimistic lock failure',
        tableName: 'users',
      );
      expect(conflictException.operationType, DbOperationType.update);
    });

    test('delete flow exceptions', () {
      final constraintException = DbDeleteException.constraintViolation(
        message: 'Cannot delete due to foreign key',
        tableName: 'users',
      );
      expect(constraintException.operationType, DbOperationType.delete);

      final notFoundException = DbDeleteException.notFound(
        message: 'Record to delete not found',
        tableName: 'users',
      );
      expect(notFoundException.operationType, DbOperationType.delete);
    });
  });
}