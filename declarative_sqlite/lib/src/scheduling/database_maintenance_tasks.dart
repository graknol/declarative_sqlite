import 'package:declarative_sqlite/src/scheduling/task_scheduler.dart';
import 'package:declarative_sqlite/src/sync/server_sync_manager.dart';

/// Built-in database maintenance tasks
class DatabaseMaintenanceTasks {
  /// Schedule fileset garbage collection
  static Future<String> scheduleFilesetGarbageCollection({
    required Future<Map<String, int>> Function() garbageCollectTask,
    Duration interval = const Duration(hours: 6),
    TaskPriority priority = TaskPriority.low,
  }) async {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Fileset Garbage Collection',
      task: garbageCollectTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 30),
    );
  }
  
  /// Schedule database optimization
  static Future<String> scheduleDatabaseOptimization({
    required Future<void> Function() optimizeTask,
    Duration interval = const Duration(days: 1),
    TaskPriority priority = TaskPriority.low,
  }) async {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Database Optimization',
      task: optimizeTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 10),
    );
  }
  
  /// Schedule sync operations using ServerSyncManager
  /// 
  /// This integrates with TaskScheduler instead of using internal timers
  /// for better resource management and fair scheduling.
  static Future<String> scheduleSyncOperation({
    required ServerSyncManager syncManager,
    Duration interval = const Duration(minutes: 15),
    TaskPriority priority = TaskPriority.normal,
  }) async {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Server Synchronization',
      task: () => syncManager.performSync(),
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 5),
    );
  }
  
  /// Schedule backup operations
  static Future<String> scheduleBackup({
    required Future<void> Function() backupTask,
    Duration interval = const Duration(hours: 12),
    TaskPriority priority = TaskPriority.normal,
  }) async {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Database Backup',
      task: backupTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 15),
    );
  }
  
  /// Schedule cleanup of old records
  static Future<String> scheduleDataCleanup({
    required Future<void> Function() cleanupTask,
    Duration interval = const Duration(days: 7),
    TaskPriority priority = TaskPriority.low,
  }) async {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Data Cleanup',
      task: cleanupTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 20),
    );
  }
  
  /// Schedule health checks
  static Future<String> scheduleHealthCheck({
    required Future<void> Function() healthCheckTask,
    Duration interval = const Duration(hours: 1),
    TaskPriority priority = TaskPriority.high,
  }) async {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Database Health Check',
      task: healthCheckTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 2),
    );
  }

  /// Schedule comprehensive database maintenance.
  /// 
  /// This is a convenience method that schedules multiple common maintenance
  /// tasks with sensible defaults for intervals and priorities.
  static Future<Map<String, String>> scheduleComprehensiveMaintenance({
    required ServerSyncManager syncManager,
    required Future<Map<String, int>> Function() garbageCollectTask,
    required Future<void> Function() optimizationTask,
    Duration syncInterval = const Duration(minutes: 15),
    Duration garbageCollectionInterval = const Duration(hours: 6),
    Duration optimizationInterval = const Duration(days: 1),
  }) async {
    final taskIds = <String, String>{};

    // Schedule sync operations
    taskIds['sync'] = await scheduleSyncOperation(
      syncManager: syncManager,
      interval: syncInterval,
      priority: TaskPriority.normal,
    );

    // Schedule fileset garbage collection
    taskIds['garbage_collection'] = await scheduleFilesetGarbageCollection(
      garbageCollectTask: garbageCollectTask,
      interval: garbageCollectionInterval,
      priority: TaskPriority.low,
    );

    // Schedule database optimization
    taskIds['optimization'] = await scheduleDatabaseOptimization(
      optimizeTask: optimizationTask,
      interval: optimizationInterval,
      priority: TaskPriority.idle,
    );

    return taskIds;
  }
}

/// Helper for device-specific scheduler configuration
class DeviceOptimizedScheduler {
  /// Initialize scheduler with device-appropriate settings
  static void initialize({bool isResourceConstrained = false}) {
    final config = isResourceConstrained 
      ? TaskSchedulerConfig.resourceConstrained
      : TaskSchedulerConfig.highPerformance;
      
    TaskScheduler.withConfig(config);
    TaskScheduler.instance.start();
  }
  
  /// Auto-detect device capabilities and initialize
  static void autoInitialize() {
    // Simple heuristic - could be enhanced with actual device detection
    final isResourceConstrained = _isResourceConstrainedDevice();
    initialize(isResourceConstrained: isResourceConstrained);
  }
  
  static bool _isResourceConstrainedDevice() {
    // Simple heuristic - in a real implementation you might check:
    // - Available RAM
    // - CPU cores
    // - Platform type (mobile vs desktop)
    // - Battery status
    // For now, assume mobile platforms are more constrained
    try {
      // This is a simplified check - real implementation would be more sophisticated
      return false; // Default to not constrained
    } catch (e) {
      return true; // If we can't determine, assume constrained
    }
  }
}