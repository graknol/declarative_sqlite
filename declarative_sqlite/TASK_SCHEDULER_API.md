# Task Scheduler API

The Task Scheduler provides fair resource management for background operations, ensuring that tasks run efficiently without overwhelming resource-constrained devices.

## Overview

The scheduler works like an operating system's task scheduler, providing:
- **Priority-based scheduling** - Higher priority tasks run first
- **Resource constraints** - Configurable limits on concurrent tasks and CPU usage
- **Fair time slicing** - Tasks are given time slices to prevent monopolization
- **Retry logic** - Failed tasks are automatically retried with exponential backoff
- **Performance monitoring** - Statistics and execution tracking

## Basic Usage

### Initialize the Scheduler

```dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

// Auto-detect device capabilities and configure appropriately
DeviceOptimizedScheduler.autoInitialize();

// Or manually configure for resource-constrained devices
DeviceOptimizedScheduler.initialize(isResourceConstrained: true);

// Or use custom configuration
final config = TaskSchedulerConfig(
  maxConcurrentTasks: 2,
  maxCpuUsage: 0.6,
  timeSliceMs: 100,
);
TaskScheduler.withConfig(config);
TaskScheduler.instance.start();
```

### Schedule One-Time Tasks

```dart
final taskId = TaskScheduler.instance.scheduleTask(
  name: 'Database Cleanup',
  task: () async {
    await performDatabaseCleanup();
  },
  priority: TaskPriority.low,
  timeout: Duration(minutes: 10),
);
```

### Schedule Recurring Tasks

```dart
final taskId = TaskScheduler.instance.scheduleRecurringTask(
  name: 'Sync Data',
  task: () async {
    await syncWithServer();
  },
  interval: Duration(minutes: 15),
  priority: TaskPriority.normal,
  timeout: Duration(minutes: 5),
);
```

### Built-in Database Maintenance Tasks

```dart
// Schedule fileset garbage collection every 6 hours
DatabaseMaintenanceTasks.scheduleFilesetGarbageCollection(
  garbageCollectTask: () => db.files.garbageCollectAll(),
  interval: Duration(hours: 6),
);

// Schedule database optimization daily
DatabaseMaintenanceTasks.scheduleDatabaseOptimization(
  optimizeTask: () => db.optimize(),
  interval: Duration(days: 1),
);

// Schedule data synchronization every 15 minutes
DatabaseMaintenanceTasks.scheduleSyncOperation(
  syncTask: () => syncManager.performSync(),
  interval: Duration(minutes: 15),
);

// Schedule backup every 12 hours
DatabaseMaintenanceTasks.scheduleBackup(
  backupTask: () => backupManager.createBackup(),
  interval: Duration(hours: 12),
);
```

## Task Priorities

Tasks are scheduled based on priority levels:

```dart
enum TaskPriority {
  critical,  // Run immediately, highest priority
  high,      // Important tasks, run soon
  normal,    // Regular tasks (default)
  low,       // Background tasks, can be deferred
  idle,      // Only run when system is idle
}
```

## Configuration Options

### Pre-defined Configurations

```dart
// For mobile devices, IoT devices, or low-power systems
TaskSchedulerConfig.resourceConstrained;

// For desktop applications or high-performance devices
TaskSchedulerConfig.highPerformance;
```

### Custom Configuration

```dart
const config = TaskSchedulerConfig(
  maxConcurrentTasks: 3,        // Max parallel tasks
  maxCpuUsage: 0.7,            // Max CPU usage (0.0 to 1.0)
  timeSliceMs: 100,            // Time slice per task
  minTaskDelayMs: 10,          // Minimum delay between tasks
  adaptiveScheduling: true,     // Adjust based on system load
);
```

## Task Management

### Monitor Task Status

```dart
// Get specific task
final task = TaskScheduler.instance.getTask(taskId);
print('Task is running: ${task?.isRunning}');
print('Retry count: ${task?.retryCount}');

// Get all tasks
final allTasks = TaskScheduler.instance.getAllTasks();

// Get scheduler statistics
final stats = TaskScheduler.instance.getStatistics();
print('Total executed: ${stats['totalTasksExecuted']}');
print('Average execution time: ${stats['averageExecutionTime']}ms');
```

### Cancel Tasks

```dart
final cancelled = TaskScheduler.instance.cancelTask(taskId);
if (cancelled) {
  print('Task cancelled successfully');
}
```

### Task Execution Callbacks

```dart
TaskScheduler.instance.setTaskExecutionCallback((result) {
  if (result.success) {
    print('Task ${result.task.name} completed in ${result.executionTime}');
  } else {
    print('Task ${result.task.name} failed: ${result.error}');
  }
});
```

## Advanced Features

### Scheduled Tasks

```dart
// Schedule task to run at specific time
final futureTime = DateTime.now().add(Duration(hours: 2));
TaskScheduler.instance.scheduleTask(
  name: 'Delayed Task',
  task: () async => await performMaintenanceTask(),
  runAt: futureTime,
);
```

### Error Handling and Retries

```dart
TaskScheduler.instance.scheduleTask(
  name: 'Resilient Task',
  task: () async {
    // Task that might fail
    await unreliableOperation();
  },
  maxRetries: 5,                    // Retry up to 5 times
  timeout: Duration(minutes: 2),    // Timeout after 2 minutes
);
```

### Performance Monitoring

```dart
final stats = TaskScheduler.instance.getStatistics();

print('Scheduler Performance:');
print('- Total tasks executed: ${stats['totalTasksExecuted']}');
print('- Total tasks failed: ${stats['totalTasksFailed']}');
print('- Average execution time: ${stats['averageExecutionTime']}ms');
print('- Currently active tasks: ${stats['activeTasks']}');
print('- Currently running tasks: ${stats['runningTasks']}');
```

## Integration Examples

### With DeclarativeDatabase

```dart
class DatabaseManager {
  late final String _garbageCollectionTaskId;
  late final String _optimizationTaskId;
  
  void setupMaintenanceTasks(DeclarativeDatabase db) {
    // Schedule fileset garbage collection
    _garbageCollectionTaskId = DatabaseMaintenanceTasks.scheduleFilesetGarbageCollection(
      garbageCollectTask: () async {
        final result = await db.files.garbageCollectAll();
        print('Cleaned ${result['filesets']} filesets, ${result['files']} files');
      },
      interval: Duration(hours: 6),
    );
    
    // Schedule database optimization
    _optimizationTaskId = DatabaseMaintenanceTasks.scheduleDatabaseOptimization(
      optimizeTask: () async {
        await db.vacuum();
        await db.analyze();
      },
      interval: Duration(days: 1),
    );
  }
  
  void dispose() {
    TaskScheduler.instance.cancelTask(_garbageCollectionTaskId);
    TaskScheduler.instance.cancelTask(_optimizationTaskId);
  }
}
```

### Resource-Aware Scheduling

```dart
class ResourceAwareApp {
  void initialize() {
    // Detect if running on resource-constrained device
    final isConstrained = Platform.isAndroid || Platform.isIOS;
    
    if (isConstrained) {
      // Use conservative settings for mobile
      final config = TaskSchedulerConfig.resourceConstrained;
      TaskScheduler.withConfig(config);
    } else {
      // Use high-performance settings for desktop
      final config = TaskSchedulerConfig.highPerformance;
      TaskScheduler.withConfig(config);
    }
    
    TaskScheduler.instance.start();
    
    // Schedule battery-friendly tasks on mobile
    if (isConstrained) {
      scheduleConstrainedTasks();
    } else {
      schedulePerformanceTasks();
    }
  }
  
  void scheduleConstrainedTasks() {
    // Less frequent, lower priority tasks for mobile
    DatabaseMaintenanceTasks.scheduleFilesetGarbageCollection(
      garbageCollectTask: () => performLightweightCleanup(),
      interval: Duration(hours: 12), // Less frequent
    );
  }
  
  void schedulePerformanceTasks() {
    // More frequent, comprehensive tasks for desktop
    DatabaseMaintenanceTasks.scheduleFilesetGarbageCollection(
      garbageCollectTask: () => performComprehensiveCleanup(),
      interval: Duration(hours: 2), // More frequent
    );
  }
}
```

## Best Practices

### 1. Choose Appropriate Priorities

```dart
// Critical: User-facing operations that must complete immediately
TaskScheduler.instance.scheduleTask(
  name: 'Save User Data',
  task: () => saveUserData(),
  priority: TaskPriority.critical,
);

// Normal: Regular background operations
TaskScheduler.instance.scheduleTask(
  name: 'Sync Changes',
  task: () => syncChanges(),
  priority: TaskPriority.normal,
);

// Low: Maintenance tasks that can be deferred
TaskScheduler.instance.scheduleTask(
  name: 'Cleanup Old Files',
  task: () => cleanupOldFiles(),
  priority: TaskPriority.low,
);
```

### 2. Set Reasonable Timeouts

```dart
// Short timeout for quick operations
TaskScheduler.instance.scheduleTask(
  name: 'Quick Sync',
  task: () => syncSmallChanges(),
  timeout: Duration(seconds: 30),
);

// Longer timeout for complex operations
TaskScheduler.instance.scheduleTask(
  name: 'Full Backup',
  task: () => createFullBackup(),
  timeout: Duration(minutes: 30),
);
```

### 3. Handle Task Results

```dart
TaskScheduler.instance.setTaskExecutionCallback((result) {
  if (!result.success) {
    // Log errors for monitoring
    logger.error('Task ${result.task.name} failed', result.error);
    
    // Handle specific error types
    if (result.error is TimeoutException) {
      // Task took too long
      notifyUserOfSlowOperation();
    } else if (result.task.hasExceededRetries) {
      // Task failed permanently
      notifyUserOfFailure(result.task.name);
    }
  }
});
```

### 4. Lifecycle Management

```dart
class AppLifecycleManager {
  void onAppStart() {
    DeviceOptimizedScheduler.autoInitialize();
    setupMaintenanceTasks();
  }
  
  void onAppPaused() {
    // Reduce task frequency when app is backgrounded
    TaskScheduler.instance.stop();
  }
  
  void onAppResumed() {
    // Resume normal scheduling when app is foregrounded
    TaskScheduler.instance.start();
  }
  
  void onAppDestroy() {
    TaskScheduler.instance.stop();
  }
}
```

This task scheduler ensures that your database maintenance operations, garbage collection, and other background tasks run efficiently without overwhelming the device, providing a smooth user experience across all platforms and device capabilities.