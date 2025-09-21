import 'package:declarative_sqlite/declarative_sqlite.dart';

void main() async {
  print('=== Task Scheduler Example ===\n');
  
  // Initialize scheduler for resource-constrained device
  DeviceOptimizedScheduler.initialize(isResourceConstrained: true);
  
  // Set up callback to monitor task execution
  TaskScheduler.instance.setTaskExecutionCallback((result) {
    if (result.success) {
      print('✅ ${result.task.name} completed in ${result.executionTime.inMilliseconds}ms');
    } else {
      print('❌ ${result.task.name} failed: ${result.error}');
    }
  });
  
  // Example 1: Schedule one-time tasks with different priorities
  print('1. Scheduling one-time tasks...');
  
  TaskScheduler.instance.scheduleTask(
    name: 'Critical User Save',
    task: () async {
      await Future.delayed(Duration(milliseconds: 50));
      print('   💾 User data saved');
    },
    priority: TaskPriority.critical,
  );
  
  TaskScheduler.instance.scheduleTask(
    name: 'Background Cleanup',
    task: () async {
      await Future.delayed(Duration(milliseconds: 100));
      print('   🧹 Background cleanup completed');
    },
    priority: TaskPriority.low,
  );
  
  TaskScheduler.instance.scheduleTask(
    name: 'Normal Sync',
    task: () async {
      await Future.delayed(Duration(milliseconds: 75));
      print('   🔄 Data synchronized');
    },
    priority: TaskPriority.normal,
  );
  
  // Wait for one-time tasks to complete
  await Future.delayed(Duration(milliseconds: 500));
  
  // Example 2: Schedule recurring maintenance tasks
  print('\n2. Scheduling recurring maintenance tasks...');
  
  final garbageCollectionId = DatabaseMaintenanceTasks.scheduleFilesetGarbageCollection(
    garbageCollectTask: () async {
      await Future.delayed(Duration(milliseconds: 200));
      print('   🗑️ Fileset garbage collection completed');
    },
    interval: Duration(seconds: 3),
    priority: TaskPriority.low,
  );
  
  final syncTaskId = DatabaseMaintenanceTasks.scheduleSyncOperation(
    syncTask: () async {
      await Future.delayed(Duration(milliseconds: 100));
      print('   📡 Remote sync completed');
    },
    interval: Duration(seconds: 2),
    priority: TaskPriority.normal,
  );
  
  final healthCheckId = DatabaseMaintenanceTasks.scheduleHealthCheck(
    healthCheckTask: () async {
      await Future.delayed(Duration(milliseconds: 50));
      print('   ❤️ Health check passed');
    },
    interval: Duration(seconds: 1),
    priority: TaskPriority.high,
  );
  
  // Let recurring tasks run for a while
  print('   Letting recurring tasks run for 8 seconds...');
  await Future.delayed(Duration(seconds: 8));
  
  // Example 3: Demonstrate task failure and retry
  print('\n3. Demonstrating task failure and retry...');
  
  var attemptCount = 0;
  TaskScheduler.instance.scheduleTask(
    name: 'Unreliable Task',
    task: () async {
      attemptCount++;
      await Future.delayed(Duration(milliseconds: 50));
      if (attemptCount < 3) {
        throw Exception('Simulated failure (attempt $attemptCount)');
      }
      print('   ✅ Unreliable task finally succeeded on attempt $attemptCount');
    },
    maxRetries: 3,
    priority: TaskPriority.normal,
  );
  
  await Future.delayed(Duration(seconds: 2));
  
  // Example 4: Scheduled task (run at specific time)
  print('\n4. Scheduling task for future execution...');
  
  final futureTime = DateTime.now().add(Duration(seconds: 2));
  TaskScheduler.instance.scheduleTask(
    name: 'Scheduled Task',
    task: () async {
      await Future.delayed(Duration(milliseconds: 50));
      print('   ⏰ Scheduled task executed at ${DateTime.now()}');
    },
    runAt: futureTime,
    priority: TaskPriority.normal,
  );
  
  await Future.delayed(Duration(seconds: 3));
  
  // Example 5: Task with timeout
  print('\n5. Demonstrating task timeout...');
  
  TaskScheduler.instance.scheduleTask(
    name: 'Slow Task',
    task: () async {
      await Future.delayed(Duration(milliseconds: 200)); // Will timeout
    },
    timeout: Duration(milliseconds: 100),
    priority: TaskPriority.normal,
  );
  
  await Future.delayed(Duration(milliseconds: 500));
  
  // Example 6: Monitor scheduler statistics
  print('\n6. Scheduler statistics:');
  final stats = TaskScheduler.instance.getStatistics();
  print('   📊 Total tasks executed: ${stats['totalTasksExecuted']}');
  print('   📊 Total tasks failed: ${stats['totalTasksFailed']}');
  print('   📊 Average execution time: ${stats['averageExecutionTime']}ms');
  print('   📊 Active tasks: ${stats['activeTasks']}');
  print('   📊 Running tasks: ${stats['runningTasks']}');
  
  // Example 7: Task management
  print('\n7. Task management:');
  final allTasks = TaskScheduler.instance.getAllTasks();
  print('   📋 Currently managed tasks:');
  for (final task in allTasks) {
    print('     - ${task.name} (Priority: ${task.priority.name}, Running: ${task.isRunning})');
  }
  
  // Cancel some recurring tasks
  print('\n8. Canceling recurring tasks...');
  TaskScheduler.instance.cancelTask(garbageCollectionId);
  TaskScheduler.instance.cancelTask(syncTaskId);
  TaskScheduler.instance.cancelTask(healthCheckId);
  print('   🛑 Recurring tasks cancelled');
  
  // Final statistics
  await Future.delayed(Duration(milliseconds: 500));
  print('\n9. Final statistics:');
  final finalStats = TaskScheduler.instance.getStatistics();
  print('   📊 Total tasks executed: ${finalStats['totalTasksExecuted']}');
  print('   📊 Total tasks failed: ${finalStats['totalTasksFailed']}');
  print('   📊 Average execution time: ${finalStats['averageExecutionTime']}ms');
  
  // Stop the scheduler
  TaskScheduler.instance.stop();
  print('\n🏁 Task scheduler example completed!');
}

/// Simulated database operations
class DatabaseOperations {
  static Future<void> garbageCollectFiles() async {
    await Future.delayed(Duration(milliseconds: 200));
    print('   🗑️ Removed 5 orphaned files');
  }
  
  static Future<void> optimizeDatabase() async {
    await Future.delayed(Duration(milliseconds: 300));
    print('   ⚡ Database optimized');
  }
  
  static Future<void> syncWithServer() async {
    await Future.delayed(Duration(milliseconds: 150));
    print('   📡 Synchronized 10 records with server');
  }
  
  static Future<void> createBackup() async {
    await Future.delayed(Duration(milliseconds: 500));
    print('   💾 Database backup created');
  }
  
  static Future<void> performHealthCheck() async {
    await Future.delayed(Duration(milliseconds: 50));
    print('   ❤️ Database health: OK');
  }
}