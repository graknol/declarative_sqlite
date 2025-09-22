import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

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
      table.text('bio').lww(); // LWW column for testing
      table.key(['id']).primary();
    });
    schemaBuilder.table('products', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('').lww();
      table.real('price').notNull(0.0);
      table.integer('stock').notNull(0);
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

  group('Record Basic Functionality', () {
    test('queryRecords returns typed Record objects', () async {
      // Insert test data
      await db.insert('users', {
        'id': 1,
        'name': 'Alice',
        'email': 'alice@example.com',
        'age': 30,
        'birth_date': '1993-05-15',
      });
      await db.insert('users', {
        'id': 2,
        'name': 'Bob',
        'email': 'bob@example.com',
        'age': 25,
        'birth_date': '1998-11-22',
      });

      // Query using Record API
      final users = await db.queryRecords(
        (q) => q.from('users').where(col('age').gt(20)).orderBy(['name']),
      );

      expect(users.length, 2);
      expect(users[0], isA<DbRecord>());
      expect(users[0].tableName, 'users');
      expect(users[0].getValue<String>('name'), 'Alice');
      expect(users[0].getValue<int>('age'), 30);
      expect(users[0].getValue<String>('email'), 'alice@example.com');
      expect(users[0].systemId, isNotNull);
    });

    test('queryTableRecords returns typed Record objects', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Charlie',
        'email': 'charlie@example.com',
        'age': 35,
      });

      final users = await db.queryTableRecords(
        'users',
        where: 'name = ?',
        whereArgs: ['Charlie'],
      );

      expect(users.length, 1);
      expect(users[0].getValue<String>('name'), 'Charlie');
      expect(users[0].getValue<int>('age'), 35);
    });
  });

  group('Record Type Conversion', () {
    test('handles DateTime conversion for date columns', () async {
      final birthDate = DateTime(1990, 3, 15);
      await db.insert('users', {
        'id': 1,
        'name': 'David',
        'email': 'david@example.com',
        'age': 33,
        'birth_date': birthDate.toIso8601String(),
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      final retrievedDate = user.getValue<DateTime>('birth_date');
      expect(retrievedDate, isA<DateTime>());
      expect(retrievedDate?.year, 1990);
      expect(retrievedDate?.month, 3);
      expect(retrievedDate?.day, 15);
    });

    test('handles null values correctly', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Eve',
        'email': 'eve@example.com',
        'age': 28,
        // birth_date is null
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      expect(user.getValue<DateTime>('birth_date'), isNull);
    });

    test('handles different numeric types', () async {
      await db.insert('products', {
        'id': 1,
        'name': 'Widget',
        'price': 19.99,
        'stock': 100,
      });

      final products = await db.queryTableRecords('products');
      final product = products.first;

      expect(product.getValue<int>('id'), 1);
      expect(product.getValue<double>('price'), 19.99);
      expect(product.getValue<int>('stock'), 100);
    });
  });

  group('Record Modification and Saving', () {
    test('setValue updates data and tracks modifications', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Frank',
        'email': 'frank@example.com',
        'age': 40,
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      expect(user.modifiedFields.isEmpty, true);

      user.setValue('name', 'Franklin');
      user.setValue('age', 41);

      expect(user.modifiedFields, containsAll(['name', 'age']));
      expect(user.getValue<String>('name'), 'Franklin');
      expect(user.getValue<int>('age'), 41);
    });

    test('save() persists changes to database', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Grace',
        'email': 'grace@example.com',
        'age': 27,
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      user.setValue('name', 'Gracie');
      user.setValue('email', 'gracie@example.com');
      await user.save();

      // Verify changes were saved
      final updatedUsers = await db.queryTableRecords('users', where: 'id = 1');
      final updatedUser = updatedUsers.first;

      expect(updatedUser.getValue<String>('name'), 'Gracie');
      expect(updatedUser.getValue<String>('email'), 'gracie@example.com');
      expect(updatedUser.modifiedFields.isEmpty, true);
    });

    test('save() clears modifiedFields after successful save', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Henry',
        'email': 'henry@example.com',
        'age': 50,
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      user.setValue('age', 51);
      expect(user.modifiedFields.isNotEmpty, true);

      await user.save();
      expect(user.modifiedFields.isEmpty, true);
    });

    test('delete() removes record from database', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Iris',
        'email': 'iris@example.com',
        'age': 32,
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      await user.delete();

      final remainingUsers = await db.queryTableRecords('users');
      expect(remainingUsers.isEmpty, true);
    });
  });

  group('LWW Column Handling', () {
    test('setValue on LWW column updates HLC', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Jack',
        'email': 'jack@example.com',
        'age': 29,
        'bio': 'Original bio',
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      final originalHlc = user.getRawValue('bio__hlc') as String?;
      expect(originalHlc, isNotNull);

      // Small delay to ensure HLC is different
      await Future.delayed(Duration(milliseconds: 1));

      user.setValue('bio', 'Updated bio');

      final newHlc = user.getRawValue('bio__hlc') as String?;
      expect(newHlc, isNotNull);
      expect(newHlc, isNot(equals(originalHlc)));
      expect(user.modifiedFields, containsAll(['bio', 'bio__hlc']));
    });

    test('LWW updates preserve conflict resolution', () async {
      await db.insert('products', {
        'id': 1,
        'name': 'Gadget',
        'price': 29.99,
        'stock': 50,
      });

      final products = await db.queryTableRecords('products');
      final product = products.first;

      // Update name (LWW column)
      product.setValue('name', 'Super Gadget');
      await product.save();

      // Verify the HLC was updated
      final updatedProducts = await db.queryTableRecords('products', where: 'id = 1');
      final updatedProduct = updatedProducts.first;

      expect(updatedProduct.getValue<String>('name'), 'Super Gadget');
      expect(updatedProduct.getRawValue('name__hlc'), isNotNull);
    });
  });

  group('System Column Access', () {
    test('provides access to system columns', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Kate',
        'email': 'kate@example.com',
        'age': 26,
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      expect(user.systemId, isNotNull);
      expect(user.systemCreatedAt, isA<DateTime>());
      expect(user.systemVersion, isA<Hlc>());
    });
  });

  group('Error Handling', () {
    test('throws error for invalid column names', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Larry',
        'email': 'larry@example.com',
        'age': 45,
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      expect(
        () => user.getValue('nonexistent_column'),
        throwsArgumentError,
      );
    });

    test('throws error when saving without system_id', () async {
      final user = RecordFactory.fromMap(
        {'id': 1, 'name': 'Test'},
        'users',
        db,
      );

      expect(
        () => user.save(),
        throwsStateError,
      );
    });

    test('throws error when deleting without system_id', () async {
      final user = RecordFactory.fromMap(
        {'id': 1, 'name': 'Test'},
        'users',
        db,
      );

      expect(
        () => user.delete(),
        throwsStateError,
      );
    });
  });

  group('DateTime Serialization', () {
    test('setValue correctly serializes DateTime to ISO string', () async {
      await db.insert('users', {
        'id': 1,
        'name': 'Monica',
        'email': 'monica@example.com',
        'age': 31,
      });

      final users = await db.queryTableRecords('users');
      final user = users.first;

      final birthDate = DateTime(1992, 8, 20, 14, 30, 0);
      user.setValue('birth_date', birthDate);

      // Check the raw database value is a string
      final rawValue = user.getRawValue('birth_date');
      expect(rawValue, isA<String>());
      expect(rawValue, birthDate.toIso8601String());

      // Save and verify it persists correctly
      await user.save();

      final reloadedUsers = await db.queryTableRecords('users', where: 'id = 1');
      final reloadedUser = reloadedUsers.first;
      final retrievedDate = reloadedUser.getValue<DateTime>('birth_date');

      expect(retrievedDate?.year, 1992);
      expect(retrievedDate?.month, 8);
      expect(retrievedDate?.day, 20);
    });
  });
}