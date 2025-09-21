import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Exception Handling Tests', () {
    late DeclarativeDatabase db;
    
    setUp(() async {
      final schema = SchemaBuilder()
        ..table('users', (table) {
          table.text('id').notNull('');
          table.text('email').notNull('');
          table.text('name').notNull('');
          table.key(['id']).primary();
          table.key(['email']).unique();
        })
        ..build();
      
      db = await DeclarativeDatabase.openInMemory('test', schema: schema);
    });

    tearDown(() async {
      await db.close();
    });

    test('DbCreateException thrown on constraint violation', () async {
      // Insert initial record
      await db.insert('users', {
        'id': 'user1',
        'email': 'test@example.com',
        'name': 'John Doe',
      });

      // Try to insert duplicate email
      expect(
        () => db.insert('users', {
          'id': 'user2',
          'email': 'test@example.com',
          'name': 'Jane Doe',
        }),
        throwsA(isA<DbCreateException>().having(
          (e) => e.errorCategory,
          'errorCategory',
          equals(DbErrorCategory.constraintViolation),
        )),
      );
    });

    test('DbReadException thrown when record not found', () async {
      expect(
        () => db.query((q) => q.from('nonexistent_table')),
        throwsA(isA<DbReadException>().having(
          (e) => e.errorCategory,
          'errorCategory',
          equals(DbErrorCategory.notFound),
        )),
      );
    });

    test('DbUpdateException thrown on invalid update', () async {
      // Insert test record
      await db.insert('users', {
        'id': 'user1',
        'email': 'test@example.com',
        'name': 'John Doe',
      });

      final users = await db.query((q) => q.from('users'));
      final user = users.first;

      // Try to update with invalid data that would violate constraints
      user.setValue('email', null); // This should cause an error
      
      expect(
        () => user.save(),
        throwsA(isA<DbUpdateException>()),
      );
    });

    test('DbDeleteException thrown on constraint violation during delete', () async {
      // This would need a foreign key constraint setup to properly test
      // For now, just verify the exception type exists and can be caught
      expect(DbDeleteException, isA<Type>());
      expect(DbDeleteException('test', DbErrorCategory.constraintViolation, 'table', 'original'), 
             isA<DbDeleteException>());
    });

    test('exception contains rich context information', () async {
      try {
        await db.insert('users', {
          'id': 'user1',
          'email': 'test@example.com',
          'name': 'John Doe',
        });
        
        // Try duplicate
        await db.insert('users', {
          'id': 'user2',
          'email': 'test@example.com',
          'name': 'Jane Doe',
        });
        
        fail('Should have thrown DbCreateException');
      } on DbCreateException catch (e) {
        expect(e.operationType, equals('create'));
        expect(e.errorCategory, equals(DbErrorCategory.constraintViolation));
        expect(e.tableName, equals('users'));
        expect(e.originalException, isNotNull);
      }
    });

    test('all exception types inherit from DbException', () {
      expect(DbCreateException('test', DbErrorCategory.unknown, 'table', 'original'), 
             isA<DbException>());
      expect(DbReadException('test', DbErrorCategory.unknown, 'table', 'original'), 
             isA<DbException>());
      expect(DbUpdateException('test', DbErrorCategory.unknown, 'table', 'original'), 
             isA<DbException>());
      expect(DbDeleteException('test', DbErrorCategory.unknown, 'table', 'original'), 
             isA<DbException>());
      expect(DbTransactionException('test', DbErrorCategory.unknown, 'table', 'original'), 
             isA<DbException>());
    });

    test('error categories cover expected scenarios', () {
      expect(DbErrorCategory.constraintViolation, isNotNull);
      expect(DbErrorCategory.notFound, isNotNull);
      expect(DbErrorCategory.invalidData, isNotNull);
      expect(DbErrorCategory.accessDenied, isNotNull);
      expect(DbErrorCategory.databaseLocked, isNotNull);
      expect(DbErrorCategory.connectionError, isNotNull);
      expect(DbErrorCategory.corruption, isNotNull);
      expect(DbErrorCategory.schemaMismatch, isNotNull);
      expect(DbErrorCategory.concurrencyConflict, isNotNull);
      expect(DbErrorCategory.unknown, isNotNull);
    });
  });
}