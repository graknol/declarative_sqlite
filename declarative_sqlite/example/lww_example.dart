import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Example demonstrating Last-Writer-Wins conflict resolution
/// for robust offline/online sync scenarios
void main() async {
  // Initialize sqflite for desktop/console apps
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  print('🚀 Last-Writer-Wins (LWW) Conflict Resolution Demo\n');
  
  // Create in-memory database
  final database = await databaseFactory.openDatabase(':memory:');
  
  // Define schema with LWW-enabled columns
  final schema = SchemaBuilder()
    .table('job_tasks', (table) => table
      .autoIncrementPrimaryKey('id')
      .text('job_id', (col) => col.notNull())
      .text('task_name', (col) => col.notNull())
      .integer('hours_used', (col) => col.lww()) // 🎯 LWW column - user can edit
      .real('hourly_rate', (col) => col.lww())   // 🎯 LWW column - server updates
      .text('notes', (col) => col.lww())         // 🎯 LWW column - both can edit
      .text('status', (col) => col.notNull().withDefaultValue('active'))
      .date('created_at')
      .index('idx_job_id', ['job_id']));
  
  // Apply schema to database
  final migrator = SchemaMigrator();
  await migrator.migrate(database, schema);
  
  // Create LWW-enabled data access layer
  final dataAccess = await LWWDataAccess.create(database: database, schema: schema);
  
  print('📝 1. Creating initial task...');
  
  // Insert initial task
  final taskId = await dataAccess.insert('job_tasks', {
    'job_id': 'JOB-2024-001',
    'task_name': 'Mobile App Development',
    'hours_used': 10,
    'hourly_rate': 75.0,
    'notes': 'Initial scope and planning',
    'status': 'active',
    'created_at': DateTime.now(),
  });
  
  var task = await dataAccess.getLWWRow('job_tasks', taskId);
  print('   Initial: ${task!['hours_used']} hours at \$${task['hourly_rate']}/hr');
  print('   Notes: "${task['notes']}"');
  
  // Simulate delay
  await Future.delayed(Duration(milliseconds: 10));
  
  print('\n👤 2. User makes local edits (immediately available in UI)...');
  
  // User updates hours - immediately available in UI
  final userEditTime = SystemColumnUtils.generateHLCTimestamp();
  await dataAccess.updateLWWColumn('job_tasks', taskId, 'hours_used', 15, explicitTimestamp: userEditTime);
  await dataAccess.updateLWWColumn('job_tasks', taskId, 'notes', 'Added authentication features');
  
  // UI gets immediate feedback
  task = await dataAccess.getLWWRow('job_tasks', taskId);
  print('   Updated: ${task!['hours_used']} hours');
  print('   Notes: "${task['notes']}"');
  
  // Show pending operations
  var pendingOps = dataAccess.getPendingOperations();
  print('   📤 ${pendingOps.length} operations pending sync');
  
  await Future.delayed(Duration(milliseconds: 10));
  
  print('\n🌐 3. Server sends updates with conflict resolution...');
  
  // Server update with older timestamp (should be rejected for hours_used)
  final olderServerTimestamp = (int.parse(userEditTime) - 5000).toString();
  
  print('   🕐 User timestamp: $userEditTime');
  print('   🕐 Server timestamp: $olderServerTimestamp (should be older)');
  
  await dataAccess.applyServerUpdate('job_tasks', taskId, {
    'hours_used': 12,  // Conflicting value with older timestamp
    'hourly_rate': 80.0, // Rate update from server
  }, olderServerTimestamp);
  
  task = await dataAccess.getLWWRow('job_tasks', taskId);
  print('   After server update (older): ${task!['hours_used']} hours at \$${task['hourly_rate']}/hr');
  print('   📊 User\'s hours_used wins (newer timestamp), server\'s rate wins');
  
  await Future.delayed(Duration(milliseconds: 10));
  
  // Server update with newer timestamp (should win)
  final newerServerTimestamp = SystemColumnUtils.generateHLCTimestamp();
  
  await dataAccess.applyServerUpdate('job_tasks', taskId, {
    'notes': 'Server: Added deployment pipeline',
  }, newerServerTimestamp);
  
  task = await dataAccess.getLWWRow('job_tasks', taskId);
  print('   After server update (newer): "${task!['notes']}"');
  print('   📊 Server\'s notes wins (newer timestamp)');
  
  print('\n🔄 4. Simulating app restart (cache cleared)...');
  
  // Create new data access instance (simulates app restart)
  final newDataAccess = await LWWDataAccess.create(database: database, schema: schema);
  
  // Data is still available from persistent storage
  task = await newDataAccess.getLWWRow('job_tasks', taskId);
  print('   After restart: ${task!['hours_used']} hours, \$${task['hourly_rate']}/hr');
  print('   Notes: "${task['notes']}"');
  print('   ✅ All conflict resolution persisted correctly');
  
  print('\n📊 5. Final state summary...');
  
  task = await newDataAccess.getLWWRow('job_tasks', taskId);
  print('   Hours Used: ${task!['hours_used']} (User won - newer timestamp)');
  print('   Hourly Rate: \$${task['hourly_rate']} (Server won - only server updated)');
  print('   Notes: "${task['notes']}" (Server won - newer timestamp)');
  print('   Status: ${task['status']} (Non-LWW column)');
  
  // Show remaining pending operations
  pendingOps = newDataAccess.getPendingOperations();
  print('   📤 ${pendingOps.length} operations still pending sync');
  
  print('\n🎯 Key Benefits Demonstrated:');
  print('   ✅ Immediate UI updates without waiting for database');
  print('   ✅ Automatic conflict resolution using timestamps');
  print('   ✅ Persistent state across app restarts');
  print('   ✅ Offline operation tracking for later sync');
  print('   ✅ Transparent to developer - just mark columns as .lww()');
  
  // Cleanup
  await database.close();
  print('\n🏁 Demo completed successfully!');
}