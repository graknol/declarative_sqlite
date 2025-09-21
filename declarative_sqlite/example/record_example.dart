import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Example demonstrating the new DbRecord functionality
/// 
/// This shows how to use the new typed Record API instead of working
/// with raw Map<String, Object?> objects.
void main() async {
  // Define schema
  final schema = SchemaBuilder()
    ..table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.text('email').notNull('');
      table.integer('age').notNull(0);
      table.date('birth_date');
      table.text('bio').lww(); // Last-Write-Wins column
      table.key(['id']).primary();
    })
    ..build();

  // Open database (this example assumes an in-memory database)
  // In a real app, you would use a file path
  final db = await DeclarativeDatabase.open(
    ':memory:',
    schema: schema,
  );

  try {
    // === OLD WAY: Working with Maps ===
    print('=== OLD WAY: Working with Maps ===');
    
    // Insert using Map
    await db.insert('users', {
      'id': 1,
      'name': 'Alice Smith',
      'email': 'alice@example.com',
      'age': 30,
      'birth_date': DateTime(1993, 5, 15).toIso8601String(),
      'bio': 'Software engineer',
    });

    // Query using Map
    final mapResults = await db.queryTable('users', where: 'id = ?', whereArgs: [1]);
    final userMap = mapResults.first;
    
    print('User (Map): ${userMap['name']} (${userMap['age']})');
    print('Birth Date (raw): ${userMap['birth_date']}');
    
    // Update using Map (manual, error-prone)
    await db.update(
      'users',
      {'age': 31, 'bio': 'Senior software engineer'},
      where: 'id = ?',
      whereArgs: [1],
    );

    // === NEW WAY: Working with DbRecord ===
    print('\n=== NEW WAY: Working with DbRecord ===');
    
    // Insert new user for DbRecord demo
    await db.insert('users', {
      'id': 2,
      'name': 'Bob Johnson',
      'email': 'bob@example.com',
      'age': 28,
      'birth_date': DateTime(1995, 8, 20).toIso8601String(),
      'bio': 'Designer',
    });

    // Query using DbRecord API
    final recordResults = await db.queryRecords(
      (q) => q.from('users').where(col('id').eq(2)),
    );
    final userRecord = recordResults.first;

    // Typed getters - no casting needed!
    print('User (DbRecord): ${userRecord.getValue<String>('name')} (${userRecord.getValue<int>('age')})');
    
    // Automatic DateTime parsing
    final birthDate = userRecord.getValue<DateTime>('birth_date');
    print('Birth Date (parsed): ${birthDate?.year}-${birthDate?.month}-${birthDate?.day}');

    // Typed setters with automatic conversion
    userRecord.setValue('age', 29);
    userRecord.setValue('birth_date', DateTime(1994, 8, 20)); // Automatically serialized
    userRecord.setValue('bio', 'Senior Designer'); // LWW column - HLC auto-updated
    
    // Save changes (only modified fields are updated)
    print('Modified fields: ${userRecord.modifiedFields}');
    await userRecord.save();
    print('Changes saved successfully!');

    // Verify the update worked
    final updatedRecord = (await db.queryTableRecords('users', where: 'id = 2')).first;
    print('Updated age: ${updatedRecord.getValue<int>('age')}');
    print('Updated bio: ${updatedRecord.getValue<String>('bio')}');

    // === Advanced Features ===
    print('\n=== Advanced Features ===');

    // System column access
    print('System ID: ${userRecord.systemId}');
    print('Created At: ${userRecord.systemCreatedAt}');
    print('Version: ${userRecord.systemVersion}');

    // LWW column handling
    final bioHlc = userRecord.getRawValue('bio__hlc');
    print('Bio HLC: $bioHlc');

    // Streaming queries with DbRecord
    print('\n=== Streaming Query Example ===');
    final userStream = db.streamRecords(
      (q) => q.from('users').where(col('age').gt(25)),
    );

    // Listen to changes (in a real app, this would be long-lived)
    final subscription = userStream.take(1).listen((users) {
      print('Found ${users.length} users over 25:');
      for (final user in users) {
        print('  - ${user.getValue<String>('name')} (age ${user.getValue<int>('age')})');
      }
    });

    // Wait for the stream to emit
    await subscription.asFuture();

    // === Error Handling ===
    print('\n=== Error Handling ===');
    
    try {
      // This will throw an error for non-existent column
      userRecord.getValue('nonexistent_column');
    } catch (e) {
      print('Expected error for invalid column: $e');
    }

    print('\nExample completed successfully!');

  } finally {
    await db.close();
  }
}

/// Helper function for creating WHERE conditions
/// (This is already exported from the library, but shown here for clarity)
Condition col(String column) => Condition(column);