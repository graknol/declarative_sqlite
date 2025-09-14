import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

void main() {
  late Database database;
  late DataAccess dataAccess;
  late SchemaBuilder schema;

  setUpAll(() async {
    // Initialize the ffi loader if not already done.
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
    
    // Insert test departments
    await dataAccess.insert('departments', {
      'name': 'Engineering',
      'manager_email': 'tech-lead@company.com'
    });
    await dataAccess.insert('departments', {
      'name': 'Marketing', 
      'manager_email': 'marketing-head@company.com'
    });
    
    // Insert test users
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

  group('AutoForm Basic Functionality', () {
    testWidgets('should create AutoForm with QueryBuilder', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      // Verify form is rendered
      expect(find.byType(AutoForm), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
      
      // Should have fields for name, email, age, salary, status (excluding id)
      expect(find.byType(TextFormField), findsNWidgets(5));
    });

    testWidgets('should auto-generate fields from table schema', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify auto-generated field labels
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      
      // Should not generate field for primary key 'id'
      expect(find.text('Id'), findsNothing);
    });

    testWidgets('should validate required fields', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      var savedData = <String, dynamic>{};
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                onSave: (data) {
                  savedData = data;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Try to save without filling required fields
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Should show validation errors for required fields
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Status is required'), findsOneWidget);
      
      // savedData should be empty since validation failed
      expect(savedData, isEmpty);
    });

    testWidgets('should validate integer fields', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter invalid integer value
      await tester.enterText(find.widgetWithText(TextFormField, '').at(2), 'not_a_number'); // age field
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Must be a valid integer'), findsOneWidget);
    });

    testWidgets('should validate real/double fields', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter invalid real value
      await tester.enterText(find.widgetWithText(TextFormField, '').at(3), 'not_a_number'); // salary field
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Must be a valid number'), findsOneWidget);
    });

    testWidgets('should save form data successfully', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      var savedData = <String, dynamic>{};
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                onSave: (data) {
                  savedData = data;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Fill in valid form data
      final nameField = find.widgetWithText(TextFormField, '').at(0);
      final emailField = find.widgetWithText(TextFormField, '').at(1);
      final ageField = find.widgetWithText(TextFormField, '').at(2);
      final salaryField = find.widgetWithText(TextFormField, '').at(3);
      final statusField = find.widgetWithText(TextFormField, '').at(4);

      await tester.enterText(nameField, 'John Doe');
      await tester.enterText(emailField, 'john@example.com');
      await tester.enterText(ageField, '35');
      await tester.enterText(salaryField, '80000.0');
      await tester.enterText(statusField, 'active');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify saved data
      expect(savedData['name'], 'John Doe');
      expect(savedData['email'], 'john@example.com');
      expect(savedData['age'], '35');
      expect(savedData['salary'], '80000.0');
      expect(savedData['status'], 'active');
    });
  });

  group('AutoForm Editing Functionality', () {
    testWidgets('should load existing record for editing', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                primaryKey: 1, // Alice's record
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should load Alice's data
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('75000.5'), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
    });

    testWidgets('should update existing record', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      var savedData = <String, dynamic>{};
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                primaryKey: 1, // Alice's record
                onSave: (data) {
                  savedData = data;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Update Alice's age
      final ageField = find.widgetWithText(TextFormField, '30');
      await tester.enterText(ageField, '31');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify updated data
      expect(savedData['age'], '31');
    });
  });

  group('AutoForm Reactive Features', () {
    testWidgets('should react to external database changes when editing', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                primaryKey: 1, // Alice's record
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);

      // Simulate external update to Alice's record
      await dataAccess.update('users', {'age': 32}, where: 'id = ?', whereArgs: [1]);

      // Allow reactive system to update
      await tester.pumpAndSettle();

      // Should reflect the external change
      expect(find.text('32'), findsOneWidget);
      expect(find.text('30'), findsNothing);
    });

    testWidgets('should handle live preview updates', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                primaryKey: 1, // Alice's record
                livePreview: true,
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('Alice Smith'), findsOneWidget);

      // Update name field (should trigger live preview)
      final nameField = find.widgetWithText(TextFormField, 'Alice Smith');
      await tester.enterText(nameField, 'Alice Johnson');
      await tester.pumpAndSettle();

      // Verify the database was updated immediately (live preview)
      final updatedRecord = await dataAccess.getByPrimaryKey('users', 1);
      expect(updatedRecord['name'], 'Alice Johnson');
    });

    testWidgets('should handle conflicting updates gracefully', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                primaryKey: 1, // Alice's record
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // User starts editing name
      final nameField = find.widgetWithText(TextFormField, 'Alice Smith');
      await tester.enterText(nameField, 'Alice Johnson');

      // Simulate external update to the same record (server merge scenario)
      await dataAccess.update('users', {'email': 'alice.smith@newcompany.com', 'age': 33}, 
          where: 'id = ?', whereArgs: [1]);

      await tester.pumpAndSettle();

      // The form should show the updated email and age from external source
      expect(find.text('alice.smith@newcompany.com'), findsOneWidget);
      expect(find.text('33'), findsOneWidget);
      
      // But preserve the user's local edit to name
      expect(find.text('Alice Johnson'), findsOneWidget);
    });
  });

  group('AutoForm Dialog Functionality', () {
    testWidgets('AutoFormDialog.showCreate should work', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    AutoFormDialog.showCreate(
                      context: context,
                      query: QueryBuilder().selectAll().from('users'),
                      title: 'Create User',
                    );
                  },
                  child: const Text('Create User'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Create User'));
      await tester.pumpAndSettle();

      // Should show dialog with form
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Create User'), findsOneWidget);
      expect(find.byType(AutoForm), findsOneWidget);
    });

    testWidgets('AutoFormDialog.showEdit should work', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    AutoFormDialog.showEdit(
                      context: context,
                      query: QueryBuilder().selectAll().from('users'),
                      primaryKey: 1,
                      title: 'Edit User',
                    );
                  },
                  child: const Text('Edit User'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Edit User'));
      await tester.pumpAndSettle();

      // Should show dialog with form pre-filled with Alice's data
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Edit User'), findsOneWidget);
      expect(find.byType(AutoForm), findsOneWidget);
      expect(find.text('Alice Smith'), findsOneWidget);
    });
  });

  group('AutoForm Custom Fields', () {
    testWidgets('should use custom fields when provided', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      final customFields = [
        AutoFormField.text('name', label: 'Full Name', required: true),
        AutoFormField.text('email', label: 'Email Address', required: true),
      ];
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                fields: customFields,
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should only show custom fields
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Age'), findsNothing); // Not in custom fields
      expect(find.text('Salary'), findsNothing); // Not in custom fields
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('should handle computed fields', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      final customFields = [
        AutoFormField.text('name', required: true),
        AutoFormField.text('email', required: true),
        AutoFormField.computed(
          'full_email',
          label: 'Full Email',
          computation: (formData) {
            final name = formData['name'] ?? '';
            final email = formData['email'] ?? '';
            return name.isEmpty ? email : '$name <$email>';
          },
          dependsOn: {'name', 'email'},
        ),
      ];
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                fields: customFields,
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Fill in name and email
      await tester.enterText(find.widgetWithText(TextFormField, '').at(0), 'John Doe');
      await tester.enterText(find.widgetWithText(TextFormField, '').at(1), 'john@example.com');
      await tester.pumpAndSettle();

      // Computed field should show combined value
      expect(find.text('John Doe <john@example.com>'), findsOneWidget);
    });
  });

  group('AutoForm Batch Functionality', () {
    testWidgets('AutoFormBatch should display multiple records', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoFormBatch(
                query: query,
                onBatchSave: (records) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show both user records
      expect(find.text('Batch Edit (2 records)'), findsOneWidget);
      expect(find.text('Record 1'), findsOneWidget);
      expect(find.text('Record 2'), findsOneWidget);
    });

    testWidgets('AutoFormBatch should handle batch updates', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      var batchSavedRecords = <Map<String, dynamic>>[];
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoFormBatch(
                query: query,
                onBatchSave: (records) {
                  batchSavedRecords = records;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Expand first record
      await tester.tap(find.text('Record 1'));
      await tester.pumpAndSettle();

      // Update Alice's age
      final ageField = find.widgetWithText(TextFormField, '30');
      await tester.enterText(ageField, '35');

      // Save batch changes
      await tester.tap(find.text('Save 1 Changes'));
      await tester.pumpAndSettle();

      // Verify batch save was called
      expect(batchSavedRecords.length, 1);
      expect(batchSavedRecords[0]['age'], '35');
      expect(batchSavedRecords[0]['id'], 1);
    });
  });

  group('AutoForm Error Handling', () {
    testWidgets('should handle invalid table name', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('invalid_table');
      
      expect(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DataAccessProvider(
                dataAccess: dataAccess,
                child: AutoForm(
                  query: query,
                  onSave: (data) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }, throwsA(isA<StateError>()));
    });

    testWidgets('should handle QueryBuilder without FROM table', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll(); // No FROM table specified
      
      expect(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DataAccessProvider(
                dataAccess: dataAccess,
                child: AutoForm(
                  query: query,
                  onSave: (data) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }, throwsA(isA<StateError>()));
    });

    testWidgets('should show error for async validation failures', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                fields: [
                  AutoFormField.text('email', 
                    validator: (value) => 'Custom async validation error'
                  ),
                ],
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Fill in email field and try to save
      await tester.enterText(find.byType(TextFormField), 'test@example.com');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Should show async validation error in snackbar
      expect(find.text('Error: Custom async validation error'), findsOneWidget);
    });
  });

  group('AutoForm Server Merge Scenarios', () {
    testWidgets('should handle server update during form edit - user wins conflict', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                primaryKey: 1, // Alice's record
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // User starts editing name
      final nameField = find.widgetWithText(TextFormField, 'Alice Smith');
      await tester.enterText(nameField, 'Alice Cooper');

      // Server updates same field while user is editing
      await dataAccess.update('users', {'name': 'Alice Server Update'}, 
          where: 'id = ?', whereArgs: [1]);

      await tester.pumpAndSettle();

      // User's local change should be preserved in the form field
      expect(find.text('Alice Cooper'), findsOneWidget);
      expect(find.text('Alice Server Update'), findsNothing);
    });

    testWidgets('should handle server update during form edit - server wins non-conflicting fields', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                primaryKey: 1, // Alice's record
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // User edits name
      final nameField = find.widgetWithText(TextFormField, 'Alice Smith');
      await tester.enterText(nameField, 'Alice Cooper');

      // Server updates different field (age) - no conflict
      await dataAccess.update('users', {'age': 35}, 
          where: 'id = ?', whereArgs: [1]);

      await tester.pumpAndSettle();

      // User's name change should be preserved
      expect(find.text('Alice Cooper'), findsOneWidget);
      
      // Server's age update should be reflected
      expect(find.text('35'), findsOneWidget);
      expect(find.text('30'), findsNothing);
    });

    testWidgets('should handle record deletion during edit', (WidgetTester tester) async {
      final query = QueryBuilder().selectAll().from('users');
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataAccessProvider(
              dataAccess: dataAccess,
              child: AutoForm(
                query: query,
                primaryKey: 1, // Alice's record
                onSave: (data) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify form loads with Alice's data
      expect(find.text('Alice Smith'), findsOneWidget);

      // External deletion of the record
      await dataAccess.delete('users', where: 'id = ?', whereArgs: [1]);

      await tester.pumpAndSettle();

      // Form should handle the case where record no longer exists
      // This might show empty fields or an error state depending on implementation
      expect(find.byType(AutoForm), findsOneWidget);
    });
  });
}