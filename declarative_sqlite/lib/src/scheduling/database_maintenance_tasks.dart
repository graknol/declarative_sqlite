import 'package:declarative_sqlite/src/scheduling/task_scheduler.dart';

/// Built-in database maintenance tasks
class DatabaseMaintenanceTasks {
  /// Schedule fileset garbage collection
  static Future<String> scheduleFilesetGarbageCollection({
    required Future<void> Function() garbageCollectTask,
    Duration interval = const Duration(hours: 6),
    TaskPriority priority = TaskPriority.low,
  }) {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Fileset Garbage Collection',
      task: garbageCollectTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 30),
    );
  }
  
  /// Schedule database optimization
  static String scheduleDatabaseOptimization({
    required Future<void> Function() optimizeTask,
    Duration interval = const Duration(days: 1),
    TaskPriority priority = TaskPriority.low,
  }) {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Database Optimization',
      task: optimizeTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 10),
    );
  }
  
  /// Schedule sync operations
  static String scheduleSyncOperation({
    required Future<void> Function() syncTask,
    Duration interval = const Duration(minutes: 15),
    TaskPriority priority = TaskPriority.normal,
  }) {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Data Synchronization',
      task: syncTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 5),
    );
  }
  
  /// Schedule backup operations
  static String scheduleBackup({
    required Future<void> Function() backupTask,
    Duration interval = const Duration(hours: 12),
    TaskPriority priority = TaskPriority.normal,
  }) {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Database Backup',
      task: backupTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 15),
    );
  }
  
  /// Schedule cleanup of old records
  static String scheduleDataCleanup({
    required Future<void> Function() cleanupTask,
    Duration interval = const Duration(days: 7),
    TaskPriority priority = TaskPriority.low,
  }) {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Data Cleanup',
      task: cleanupTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 20),
    );
  }
  
  /// Schedule health checks
  static String scheduleHealthCheck({
    required Future<void> Function() healthCheckTask,
    Duration interval = const Duration(hours: 1),
    TaskPriority priority = TaskPriority.high,
  }) {
    return TaskScheduler.instance.scheduleRecurringTask(
      name: 'Database Health Check',
      task: healthCheckTask,
      interval: interval,
      priority: priority,
      timeout: const Duration(minutes: 2),
    );
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