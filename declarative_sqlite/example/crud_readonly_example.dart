import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Example demonstrating CRUD vs Read-only record functionality
/// 
/// Shows the difference between:
/// - Table queries (CRUD-enabled by default)
/// - View queries (read-only by default) 
/// - forUpdate() queries (CRUD-enabled for specified table)
/// - reload() functionality
void main() async {
  // Define schema with tables and views
  final schema = SchemaBuilder()
    ..table('users', (table) {
      table.integer('id').notNull(0);
      table.text('name').notNull('');
      table.text('email').notNull('');
      table.integer('age').notNull(0);
      table.text('bio').lww();
      table.key(['id']).primary();
    })
    ..table('profiles', (table) {
      table.integer('user_id').notNull(0);
      table.text('description').notNull('');
      table.text('website');
      table.key(['user_id']).primary();
    })
    ..view('user_details', (view) {
      view.select('users.id')
          .select('users.name')
          .select('users.email')
          .select('users.age')
          .select('profiles.description')
          .select('profiles.website')
          .from('users')
          .leftJoin('profiles', 'profiles.user_id = users.id');
    })
    ..build();

  final db = await DeclarativeDatabase.open(':memory:', schema: schema);

  try {
    print('=== CRUD vs Read-Only Records Demo ===\n');

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
      'description': 'Passionate about clean code',
      'website': 'https://alice.dev',
    });

    // === 1. Table Queries (CRUD-enabled by default) ===
    print('1. Table Query (CRUD-enabled):');
    final users = await db.queryTableRecords('users');
    final user = users.first;
    
    print('   isReadOnly: ${user.isReadOnly}');
    print('   isCrudEnabled: ${user.isCrudEnabled}');
    print('   updateTableName: ${user.updateTableName}');
    
    // Can modify and save
    user.setValue('name', 'Alice Johnson');
    user.setValue('age', 31);
    await user.save();
    print('   ✓ Successfully updated user name and age\n');

    // === 2. View Queries (Read-only by default) ===
    print('2. View Query (Read-only):');
    final userDetails = await db.queryTableRecords('user_details');
    final userDetail = userDetails.first;
    
    print('   isReadOnly: ${userDetail.isReadOnly}');
    print('   isCrudEnabled: ${userDetail.isCrudEnabled}');
    print('   updateTableName: ${userDetail.updateTableName}');
    
    try {
      userDetail.setValue('name', 'Should Fail');
    } catch (e) {
      print('   ✓ Cannot modify read-only record: ${e.toString().split(':').last.trim()}\n');
    }

    // === 3. forUpdate Queries (CRUD-enabled for specified table) ===
    print('3. View Query with forUpdate (CRUD-enabled):');
    final updatableUserDetails = await db.queryRecords(
      (q) => q.from('user_details').forUpdate('users'),
    );
    final updatableUserDetail = updatableUserDetails.first;
    
    print('   isReadOnly: ${updatableUserDetail.isReadOnly}');
    print('   isCrudEnabled: ${updatableUserDetail.isCrudEnabled}');
    print('   updateTableName: ${updatableUserDetail.updateTableName}');
    
    // Can modify columns that exist in the target table
    updatableUserDetail.setValue('name', 'Alice Modified');
    updatableUserDetail.setValue('email', 'alice.modified@example.com');
    await updatableUserDetail.save();
    print('   ✓ Successfully updated user via view query\n');

    // === 4. Complex Join with forUpdate ===
    print('4. Complex Join Query with forUpdate:');
    final joinResults = await db.queryRecords(
      (q) => q.from('users')
          .select('users.system_id')
          .select('users.system_version')
          .select('users.name')
          .select('users.email')
          .select('profiles.description as profile_desc')
          .select('profiles.website')
          .leftJoin('profiles', 'profiles.user_id = users.id')
          .forUpdate('users'),
    );
    
    final joinResult = joinResults.first;
    print('   Can access joined data: ${joinResult.getRawValue('profile_desc')}');
    print('   Can access joined data: ${joinResult.getRawValue('website')}');
    
    // Can only modify columns from the target table (users)
    joinResult.setValue('name', 'Alice Final');
    await joinResult.save();
    print('   ✓ Updated users table via complex join\n');

    // === 5. Reload Functionality ===
    print('5. Reload Functionality:');
    final reloadUser = (await db.queryTableRecords('users', where: 'id = 1')).first;
    
    print('   Original name: ${reloadUser.getValue<String>('name')}');
    
    // Modify in memory
    reloadUser.setValue('name', 'Temporary Name');
    print('   Modified name: ${reloadUser.getValue<String>('name')}');
    print('   Modified fields: ${reloadUser.modifiedFields}');
    
    // Reload from database
    await reloadUser.reload();
    print('   After reload: ${reloadUser.getValue<String>('name')}');
    print('   Modified fields: ${reloadUser.modifiedFields}');
    print('   ✓ Reload restored original data and cleared modifications\n');

    // === 6. Error Handling Examples ===
    print('6. Error Handling:');
    
    // forUpdate with non-existent table
    try {
      await db.queryRecords((q) => q.from('users').forUpdate('nonexistent'));
    } catch (e) {
      print('   ✓ forUpdate validation: ${e.toString().split(':').last.trim()}');
    }
    
    // forUpdate without system_id
    try {
      await db.queryRecords(
        (q) => q.from('users').select('name').forUpdate('users'),
      );
    } catch (e) {
      print('   ✓ Missing system_id: ${e.toString().split(':').last.trim()}');
    }
    
    // Reload on read-only record
    try {
      await userDetail.reload();
    } catch (e) {
      print('   ✓ Read-only reload: ${e.toString().split(':').last.trim()}');
    }

    // === 7. Streaming Queries ===
    print('\n7. Streaming Queries:');
    
    // CRUD-enabled stream
    final crudStream = db.streamRecords((q) => q.from('users'));
    final crudResults = await crudStream.first;
    print('   Table stream - isCrudEnabled: ${crudResults.first.isCrudEnabled}');
    
    // Read-only stream  
    final readOnlyStream = db.streamRecords((q) => q.from('user_details'));
    final readOnlyResults = await readOnlyStream.first;
    print('   View stream - isReadOnly: ${readOnlyResults.first.isReadOnly}');
    
    // forUpdate stream
    final forUpdateStream = db.streamRecords(
      (q) => q.from('user_details').forUpdate('users'),
    );
    final forUpdateResults = await forUpdateStream.first;
    print('   forUpdate stream - isCrudEnabled: ${forUpdateResults.first.isCrudEnabled}');

    print('\n=== Demo completed successfully! ===');

  } finally {
    await db.close();
  }
}

// Helper function (exported from library)
Condition col(String column) => Condition(column);