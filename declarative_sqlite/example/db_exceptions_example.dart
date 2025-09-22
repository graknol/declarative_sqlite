import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Example demonstrating the database exception handling system
/// 
/// Shows how platform-specific database exceptions are automatically
/// wrapped into developer-friendly exception types similar to REST API status codes.
void main() async {
  // Define schema with constraints to demonstrate exception handling
  final schema = SchemaBuilder()
    ..table('users', (table) {
      table.integer('id').notNull(0);
      table.text('email').notNull('');
      table.text('name').notNull('');
      table.integer('age').notNull(0);
      table.key(['id']).primary();
      table.key(['email']).unique();
    })
    ..table('profiles', (table) {
      table.integer('user_id').notNull(0);
      table.text('bio').notNull('');
      table.key(['user_id']).primary();
      table.key(['user_id']).foreignKey('users', ['id']);
    })
    ..build();

  final db = await DeclarativeDatabase.open(':memory:', schema: schema);

  try {
    print('=== Database Exception Handling Demo ===\n');

    // === 1. Successful Operations ===
    print('1. Successful Operations:');
    
    final userId = await db.insert('users', {
      'id': 1,
      'email': 'alice@example.com',
      'name': 'Alice Smith',
      'age': 30,
    });
    print('   ✓ User created with ID: $userId');

    await db.insert('profiles', {
      'user_id': 1,
      'bio': 'Software engineer passionate about clean code',
    });
    print('   ✓ Profile created successfully\n');

    // === 2. Create Exceptions (DbCreateException) ===
    print('2. Create Operation Failures:');

    // Primary key constraint violation
    try {
      await db.insert('users', {
        'id': 1, // Same ID as above
        'email': 'another@example.com',
        'name': 'Another User',
        'age': 25,
      });
    } catch (e) {
      if (e is DbCreateException) {
        print('   🚫 DbCreateException caught:');
        print('      Operation: ${e.operationType}');
        print('      Category: ${e.errorCategory}');
        print('      Table: ${e.tableName}');
        print('      Message: ${e.message}');
        print('      Original: ${e.originalException?.runtimeType}');
      } else {
        print('   🚫 Unexpected exception: ${e.runtimeType}');
      }
    }

    // Unique constraint violation
    try {
      await db.insert('users', {
        'id': 2,
        'email': 'alice@example.com', // Same email as first user
        'name': 'Alice Clone',
        'age': 28,
      });
    } catch (e) {
      if (e is DbCreateException) {
        print('   🚫 Unique constraint violation:');
        print('      Category: ${e.errorCategory}');
        print('      Message: ${e.message}');
      }
    }

    // === 3. Read Exceptions (DbReadException) ===
    print('\n3. Read Operation Failures:');

    try {
      await db.queryTable('nonexistent_table');
    } catch (e) {
      if (e is DbReadException) {
        print('   🚫 DbReadException caught:');
        print('      Operation: ${e.operationType}');
        print('      Category: ${e.errorCategory}');
        print('      Message: ${e.message}');
      }
    }

    // === 4. Update Exceptions (DbUpdateException) ===
    print('\n4. Update Operation Scenarios:');

    // Successful update
    final updateCount = await db.update(
      'users',
      {'age': 31},
      where: 'id = ?',
      whereArgs: [1],
    );
    print('   ✓ Updated $updateCount record(s)');

    // Update with no matching records (not an error in SQLite)
    final noUpdateCount = await db.update(
      'users',
      {'age': 25},
      where: 'id = ?',
      whereArgs: [999], // Non-existent ID
    );
    print('   ℹ️ Updated $noUpdateCount record(s) (non-existent ID)');

    // === 5. Delete Exceptions (DbDeleteException) ===
    print('\n5. Delete Operation Failures:');

    try {
      // Try to delete user that has dependent profile (foreign key constraint)
      await db.delete('users', where: 'id = ?', whereArgs: [1]);
      print('   ℹ️ Delete succeeded (foreign keys might not be enabled)');
    } catch (e) {
      if (e is DbDeleteException) {
        print('   🚫 DbDeleteException caught:');
        print('      Operation: ${e.operationType}');
        print('      Category: ${e.errorCategory}');
        print('      Message: ${e.message}');
      }
    }

    // === 6. Transaction Exceptions (DbTransactionException) ===
    print('\n6. Transaction Failures:');

    try {
      await db.transaction((txn) async {
        // Insert a valid record
        await txn.insert('users', {
          'id': 3,
          'email': 'bob@example.com',
          'name': 'Bob Johnson',
          'age': 25,
        });

        // Force a failure to trigger rollback
        throw Exception('Simulated business logic error');
      });
    } catch (e) {
      if (e is DbTransactionException) {
        print('   🚫 DbTransactionException caught:');
        print('      Operation: ${e.operationType}');
        print('      Category: ${e.errorCategory}');
        print('      Message: ${e.message}');
      } else {
        print('   🚫 Transaction failed with: ${e.runtimeType}');
      }
    }

    // Verify transaction was rolled back
    final users = await db.queryTable('users');
    print('   ℹ️ User count after failed transaction: ${users.length}');

    // === 7. DbRecord Exception Handling ===
    print('\n7. DbRecord Exception Handling:');

    final userRecords = await db.queryTableRecords('users');
    if (userRecords.isNotEmpty) {
      final user = userRecords.first;
      
      // Successful operation
      user.setValue('name', 'Alice Updated');
      await user.save();
      print('   ✓ DbRecord save succeeded');

      // Try to create duplicate record
      try {
        final duplicateUser = RecordFactory.fromTable({
          'id': 1, // Same ID as existing user
          'email': 'duplicate@example.com',
          'name': 'Duplicate User',
          'age': 35,
        }, 'users', db);

        await duplicateUser.insert();
      } catch (e) {
        if (e is DbCreateException) {
          print('   🚫 DbRecord insert failed:');
          print('      Category: ${e.errorCategory}');
          print('      Message: ${e.message}');
        }
      }
    }

    // === 8. Exception Categories Demo ===
    print('\n8. Exception Categories Available:');
    print('   • constraintViolation - Unique, foreign key, primary key violations');
    print('   • notFound - Table, column, or record not found');
    print('   • invalidData - Data type mismatches, invalid values');
    print('   • accessDenied - Permission or security errors');
    print('   • databaseLocked - Database busy or locked');
    print('   • connectionError - Connection or network issues');
    print('   • corruption - Database file corruption');
    print('   • schemaMismatch - Schema or migration problems');
    print('   • concurrencyConflict - Optimistic locking conflicts');
    print('   • unknown - Unexpected or unclassified errors');

    // === 9. Business Flow Mapping ===
    print('\n9. Business Flow Exception Mapping:');
    print('   • DbCreateException - "Can\'t create the record"');
    print('   • DbReadException - "Can\'t read the record"');
    print('   • DbUpdateException - "Can\'t update the record"');
    print('   • DbDeleteException - "Can\'t delete the record"');
    print('   • DbTransactionException - "Transaction failed"');
    print('   • DbConnectionException - "Database connection issues"');
    print('   • DbMigrationException - "Schema migration problems"');

    // === 10. Exception Handling Best Practices ===
    print('\n10. Exception Handling Best Practices:');

    try {
      await db.insert('users', {
        'id': 2,
        'email': 'test@example.com',
        'name': 'Test User',
        'age': 25,
      });
    } on DbCreateException catch (e) {
      // Handle specific create failures
      switch (e.errorCategory) {
        case DbErrorCategory.constraintViolation:
          print('   💡 Handle constraint violation: Show user-friendly error');
          break;
        case DbErrorCategory.invalidData:
          print('   💡 Handle invalid data: Validate and retry');
          break;
        default:
          print('   💡 Handle other create errors: Log and notify user');
      }
    } on DbException catch (e) {
      // Handle any other database exception
      print('   💡 Handle general database error: ${e.operationType}');
    } catch (e) {
      // Handle unexpected exceptions
      print('   💡 Handle unexpected error: $e');
    }

    print('\n=== Demo completed successfully! ===');
    print('All database exceptions are now wrapped in developer-friendly types');
    print('similar to REST API status codes (404, 409, 400, etc.)');

  } finally {
    await db.close();
  }
}

// Helper function (exported from library)
Condition col(String column) => Condition(column);