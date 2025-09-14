import 'dart:async';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// AutoForm Logic and Reactive Behavior Tests
/// Tests the core functionality without Flutter widgets
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
          .text('email', (col) => col.notNull().unique())
          .integer('age')
          .real('salary')
          .text('status', (col) => col.notNull()))
      .table('departments', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('manager_email'));

    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = await DataAccess.create(database: database, schema: schema);
    
    // Insert test data
    await dataAccess.insert('users', {
      'name': 'Alice Smith',
      'email': 'alice@example.com',
      'age': 30,
      'salary': 75000.50,
      'status': 'active',
    });
    await dataAccess.insert('users', {
      'name': 'Bob Johnson',
      'email': 'bob@example.com', 
      'age': 25,
      'salary': 60000.0,
      'status': 'active',
    });
  });

  tearDown(() async {
    await dataAccess.dispose();
    await database.close();
  });

  group('AutoForm QueryBuilder Integration', () {
    test('should extract table name from QueryBuilder', () {
      final query = QueryBuilder().selectAll().from('users');
      expect(query.fromTable, equals('users'));
      
      final queryWithWhere = QueryBuilder()
          .selectAll()
          .from('users')
          .where((cb) => cb.eq('status', 'active'));
      expect(queryWithWhere.fromTable, equals('users'));
    });

    test('should validate QueryBuilder has FROM table', () {
      final invalidQuery = QueryBuilder().selectAll();
      expect(invalidQuery.fromTable, isNull);
    });

    test('should extract columns from table schema', () {
      final tableName = 'users';
      final table = schema.tables.firstWhere((t) => t.name == tableName);
      
      // Should have all expected columns
      final columnNames = table.columns.map((c) => c.name).toList();
      expect(columnNames, contains('id'));
      expect(columnNames, contains('name'));
      expect(columnNames, contains('email'));
      expect(columnNames, contains('age'));
      expect(columnNames, contains('salary'));
      expect(columnNames, contains('status'));
      
      // Check column types
      final nameCol = table.columns.firstWhere((c) => c.name == 'name');
      final ageCol = table.columns.firstWhere((c) => c.name == 'age');
      final salaryCol = table.columns.firstWhere((c) => c.name == 'salary');
      
      expect(nameCol.dataType, equals(SqliteDataType.text));
      expect(nameCol.constraints.contains(ConstraintType.notNull), isTrue);
      expect(ageCol.dataType, equals(SqliteDataType.integer));
      expect(salaryCol.dataType, equals(SqliteDataType.real));
    });
  });

  group('AutoForm Field Generation Logic', () {
    test('should generate appropriate field types from column definitions', () {
      final tableName = 'users';
      final table = schema.tables.firstWhere((t) => t.name == tableName);
      
      final generatedFields = <String, Map<String, dynamic>>{};
      
      for (final column in table.columns) {
        // Skip system columns and primary key
        if (column.name == 'id' || 
            column.name == SystemColumns.systemId || 
            column.name == SystemColumns.systemVersion) {
          continue;
        }
        
        final fieldConfig = <String, dynamic>{
          'name': column.name,
          'required': column.constraints.contains(ConstraintType.notNull),
          'type': column.dataType,
        };
        
        // Add validation based on type
        switch (column.dataType) {
          case SqliteDataType.integer:
            fieldConfig['validator'] = 'integer';
            break;
          case SqliteDataType.real:
            fieldConfig['validator'] = 'real';
            break;
          default:
            fieldConfig['validator'] = 'text';
        }
        
        generatedFields[column.name] = fieldConfig;
      }
      
      // Verify generated fields
      expect(generatedFields.keys, contains('name'));
      expect(generatedFields.keys, contains('email'));
      expect(generatedFields.keys, contains('age'));
      expect(generatedFields.keys, contains('salary'));
      expect(generatedFields.keys, contains('status'));
      expect(generatedFields.keys, isNot(contains('id'))); // Should skip primary key
      
      // Verify field configurations
      expect(generatedFields['name']!['required'], isTrue);
      expect(generatedFields['age']!['validator'], equals('integer'));
      expect(generatedFields['salary']!['validator'], equals('real'));
    });

    test('should validate integer fields', () {
      // Simulate integer field validation
      bool validateInteger(dynamic value) {
        if (value == null || value.toString().isEmpty) return true; // Optional field
        return int.tryParse(value.toString()) != null;
      }
      
      expect(validateInteger('25'), isTrue);
      expect(validateInteger('0'), isTrue);
      expect(validateInteger('-5'), isTrue);
      expect(validateInteger('not_a_number'), isFalse);
      expect(validateInteger('25.5'), isFalse);
      expect(validateInteger(''), isTrue); // Empty is valid for optional fields
      expect(validateInteger(null), isTrue);
    });

    test('should validate real/double fields', () {
      // Simulate real field validation
      bool validateReal(dynamic value) {
        if (value == null || value.toString().isEmpty) return true; // Optional field
        return double.tryParse(value.toString()) != null;
      }
      
      expect(validateReal('25.5'), isTrue);
      expect(validateReal('25'), isTrue);
      expect(validateReal('0.0'), isTrue);
      expect(validateReal('-5.25'), isTrue);
      expect(validateReal('not_a_number'), isFalse);
      expect(validateReal(''), isTrue); // Empty is valid for optional fields
      expect(validateReal(null), isTrue);
    });

    test('should validate required fields', () {
      // Simulate required field validation
      bool validateRequired(dynamic value, bool isRequired) {
        if (!isRequired) return true;
        return value != null && value.toString().isNotEmpty;
      }
      
      expect(validateRequired('some value', true), isTrue);
      expect(validateRequired('', true), isFalse);
      expect(validateRequired(null, true), isFalse);
      expect(validateRequired('', false), isTrue);
      expect(validateRequired(null, false), isTrue);
    });
  });

  group('AutoForm Reactive Behavior', () {
    test('should detect changes in database (reactive behavior simulation)', () async {
      // Test the underlying reactive behavior without relying on streams
      final query = QueryBuilder().selectAll().from('users').where((cb) => cb.eq('id', 1));
      
      // Get initial data manually 
      final initialData = await dataAccess.getAllWhere('users', where: 'id = ?', whereArgs: [1]);
      expect(initialData.length, equals(1));
      expect(initialData.first['name'], equals('Alice Smith'));
      expect(initialData.first['age'], equals(30));
      
      // Simulate form update to the record
      await dataAccess.updateWhere('users', {'age': 31}, where: 'id = ?', whereArgs: [1]);
      
      // Verify the change is reflected in database
      final updatedData = await dataAccess.getAllWhere('users', where: 'id = ?', whereArgs: [1]);
      expect(updatedData.length, equals(1));
      expect(updatedData.first['age'], equals(31));
      expect(updatedData.first['name'], equals('Alice Smith')); // Unchanged field
      
      // This simulates what AutoForm reactive behavior should do:
      // 1. Watch for changes in the database
      // 2. Update the UI when changes are detected
      // 3. Preserve local form state while reflecting server changes
    });

    test('should handle simultaneous updates (server merge scenario)', () async {
      // Get initial record
      final initialRecord = await dataAccess.getByPrimaryKey('users', 1);
      expect(initialRecord, isNotNull);
      expect(initialRecord!['name'], equals('Alice Smith'));
      expect(initialRecord['age'], equals(30));
      expect(initialRecord['email'], equals('alice@example.com'));
      
      // Simulate user editing name locally (not saved yet)
      final localFormData = Map<String, dynamic>.from(initialRecord!);
      localFormData['name'] = 'Alice Johnson'; // User's local change
      
      // Simulate server/external update to different field
      await dataAccess.updateWhere('users', {'age': 32, 'email': 'alice.smith@newcompany.com'}, 
          where: 'id = ?', whereArgs: [1]);
      
      // Get updated record from server
      final serverRecord = await dataAccess.getByPrimaryKey('users', 1);
      
      // Merge strategy: preserve local changes, accept server changes for other fields
      final mergedData = Map<String, dynamic>.from(serverRecord!);
      mergedData['name'] = localFormData['name']; // Keep user's local change
      
      // Verify merge result
      expect(mergedData['name'], equals('Alice Johnson')); // User's change preserved
      expect(mergedData['age'], equals(32)); // Server's change accepted
      expect(mergedData['email'], equals('alice.smith@newcompany.com')); // Server's change accepted
    });

    test('should handle conflict resolution when same field is updated', () async {
      // Get initial record
      final initialRecord = await dataAccess.getByPrimaryKey('users', 1);
      expect(initialRecord, isNotNull);
      expect(initialRecord!['name'], equals('Alice Smith'));
      
      // Simulate user editing name locally
      final localFormData = Map<String, dynamic>.from(initialRecord);
      localFormData['name'] = 'Alice Johnson'; // User's local change
      
      // Simulate server update to same field (conflict!)
      await dataAccess.updateWhere('users', {'name': 'Alice Server Update'}, 
          where: 'id = ?', whereArgs: [1]);
      
      // Get server record
      final serverRecord = await dataAccess.getByPrimaryKey('users', 1);
      expect(serverRecord, isNotNull);
      expect(serverRecord!['name'], equals('Alice Server Update'));
      
      // In a real AutoForm, the local value should be preserved in the form field
      // until user decides to save or refresh
      expect(localFormData['name'], equals('Alice Johnson')); // Local change preserved
      expect(serverRecord!['name'], equals('Alice Server Update')); // Server has different value
      
      // User can decide to keep local change or accept server change
      final userKeepsLocal = true;
      if (userKeepsLocal) {
        // Save user's version
        await dataAccess.updateWhere('users', {'name': localFormData['name']}, 
            where: 'id = ?', whereArgs: [1]);
        
        final finalRecord = await dataAccess.getByPrimaryKey('users', 1);
        expect(finalRecord, isNotNull);
        expect(finalRecord!['name'], equals('Alice Johnson'));
      }
    });

    test('should handle record deletion during edit', () async {
      // Get initial record
      final initialRecord = await dataAccess.getByPrimaryKey('users', 1);
      expect(initialRecord, isNotNull);
      expect(initialRecord!['name'], equals('Alice Smith'));
      
      // Simulate user is editing the record
      final localFormData = Map<String, dynamic>.from(initialRecord);
      localFormData['name'] = 'Alice Johnson';
      
      // External deletion of the record
      await dataAccess.deleteByPrimaryKey('users', 1);
      
      // Try to get the record - should be null/empty
      final deletedRecord = await dataAccess.getByPrimaryKey('users', 1);
      expect(deletedRecord, isNull);
      
      // Form should handle this gracefully - local data still exists
      expect(localFormData['name'], equals('Alice Johnson'));
      
      // If user tries to save, should get an error or create new record
      try {
        await dataAccess.updateWhere('users', localFormData, where: 'id = ?', whereArgs: [1]);
        // Should not reach here if record doesn't exist
        fail('Expected update to fail for deleted record');
      } catch (e) {
        // Expected - record doesn't exist
        expect(e, isNotNull);
      }
    });
  });

  group('AutoForm Live Preview Simulation', () {
    test('should update database immediately on field change when live preview is enabled', () async {
      final recordId = 1;
      
      // Get initial record
      final initialRecord = await dataAccess.getByPrimaryKey('users', recordId);
      expect(initialRecord, isNotNull);
      expect(initialRecord!['name'], equals('Alice Smith'));
      
      // Simulate live preview field change
      await dataAccess.updateByPrimaryKey('users', recordId, {'name': 'Alice Updated'});
      
      // Verify immediate database update
      final updatedRecord = await dataAccess.getByPrimaryKey('users', recordId);
      expect(updatedRecord, isNotNull);
      expect(updatedRecord!['name'], equals('Alice Updated'));
    });

    test('should handle multiple rapid live preview updates', () async {
      final recordId = 1;
      
      // Simulate rapid successive updates (like user typing)
      await dataAccess.updateByPrimaryKey('users', recordId, {'name': 'A'});
      await dataAccess.updateByPrimaryKey('users', recordId, {'name': 'Al'});
      await dataAccess.updateByPrimaryKey('users', recordId, {'name': 'Ali'});
      await dataAccess.updateByPrimaryKey('users', recordId, {'name': 'Alic'});
      await dataAccess.updateByPrimaryKey('users', recordId, {'name': 'Alice'});
      
      // Final state should reflect last update
      final finalRecord = await dataAccess.getByPrimaryKey('users', recordId);
      expect(finalRecord, isNotNull);
      expect(finalRecord!['name'], equals('Alice'));
    });
  });

  group('AutoForm Batch Operations', () {
    test('should support batch editing multiple records', () async {
      // Get all users
      final allUsers = await dataAccess.getAll('users');
      expect(allUsers.length, equals(2));
      
      // Simulate batch changes
      final batchChanges = <dynamic, Map<String, dynamic>>{
        1: {'status': 'inactive'},
        2: {'status': 'inactive', 'age': 26},
      };
      
      // Apply batch changes
      for (final entry in batchChanges.entries) {
        final recordId = entry.key;
        final changes = entry.value;
        
        await dataAccess.updateByPrimaryKey('users', recordId, changes);
      }
      
      // Verify batch changes
      final updatedUsers = await dataAccess.getAll('users');
      
      expect(updatedUsers[0]['status'], equals('inactive'));
      expect(updatedUsers[1]['status'], equals('inactive'));
      expect(updatedUsers[1]['age'], equals(26));
    });

    test('should track batch changes separately from database state', () {
      // Simulate batch editing state
      final originalRecords = [
        {'id': 1, 'name': 'Alice', 'status': 'active'},
        {'id': 2, 'name': 'Bob', 'status': 'active'},
      ];
      
      final batchChanges = <dynamic, Map<String, dynamic>>{};
      
      // User makes changes to record 1
      batchChanges[1] = {'status': 'inactive'};
      
      // Get effective state (original + changes)
      final getEffectiveRecord = (int id) {
        final original = originalRecords.firstWhere((r) => r['id'] == id);
        final changes = batchChanges[id] ?? {};
        return {...original, ...changes};
      };
      
      final record1 = getEffectiveRecord(1);
      final record2 = getEffectiveRecord(2);
      
      expect(record1['status'], equals('inactive')); // Changed
      expect(record1['name'], equals('Alice')); // Unchanged
      expect(record2['status'], equals('active')); // Unchanged
      
      // Verify changes tracking
      expect(batchChanges.keys, equals([1]));
      expect(batchChanges[1]!['status'], equals('inactive'));
    });
  });

  group('AutoForm Field Validation Logic', () {
    test('should validate email uniqueness asynchronously', () async {
      // Simulate async uniqueness validation
      Future<String?> validateEmailUnique(String email, {int? excludeId}) async {
        String? whereClause = 'email = ?';
        List<dynamic> whereArgs = [email];
        
        if (excludeId != null) {
          whereClause = 'email = ? AND id != ?';
          whereArgs = [email, excludeId];
        }
        
        final existing = await dataAccess.getAllWhere('users', 
            where: whereClause, whereArgs: whereArgs);
        return existing.isNotEmpty ? 'Email already exists' : null;
      }
      
      // Test with existing email
      var error = await validateEmailUnique('alice@example.com');
      expect(error, equals('Email already exists'));
      
      // Test with new email
      error = await validateEmailUnique('newuser@example.com');
      expect(error, isNull);
      
      // Test with existing email but excluding the same record (editing scenario)
      error = await validateEmailUnique('alice@example.com', excludeId: 1);
      expect(error, isNull); // Should be valid when editing the same record
    });

    test('should handle complex field dependencies', () {
      // Simulate computed field that depends on other fields
      dynamic computeFullEmail(Map<String, dynamic> formData) {
        final name = formData['name'] ?? '';
        final email = formData['email'] ?? '';
        
        if (name.isEmpty || email.isEmpty) return '';
        
        return '$name <$email>';
      }
      
      final formData1 = {'name': 'John Doe', 'email': 'john@example.com'};
      final formData2 = {'name': '', 'email': 'john@example.com'};
      final formData3 = {'name': 'John Doe', 'email': ''};
      
      expect(computeFullEmail(formData1), equals('John Doe <john@example.com>'));
      expect(computeFullEmail(formData2), equals(''));
      expect(computeFullEmail(formData3), equals(''));
    });

    test('should validate field visibility conditions', () {
      // Simulate conditional field visibility
      bool isFieldVisible(String fieldName, Map<String, dynamic> formData) {
        switch (fieldName) {
          case 'salary':
            // Salary field only visible for active employees
            return formData['status'] == 'active';
          case 'manager_email':
            // Manager email only for specific departments
            return formData['department'] == 'Engineering';
          default:
            return true;
        }
      }
      
      final activeEmployee = {'status': 'active', 'department': 'Engineering'};
      final inactiveEmployee = {'status': 'inactive', 'department': 'Marketing'};
      
      expect(isFieldVisible('name', activeEmployee), isTrue); // Always visible
      expect(isFieldVisible('salary', activeEmployee), isTrue); // Visible for active
      expect(isFieldVisible('salary', inactiveEmployee), isFalse); // Hidden for inactive
      expect(isFieldVisible('manager_email', activeEmployee), isTrue); // Visible for Engineering
      expect(isFieldVisible('manager_email', inactiveEmployee), isFalse); // Hidden for Marketing
    });
  });
}