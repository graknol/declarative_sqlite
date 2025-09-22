import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math';
import '../database.dart';

/// Priority levels for scheduled tasks
enum TaskPriority {
  /// Highest priority - critical tasks that should run immediately
  critical(4),
  
  /// High priority - important tasks that should run soon
  high(3),
  
  /// Normal priority - regular tasks (default)
  normal(2),
  
  /// Low priority - background tasks that can be deferred
  low(1),
  
  /// Lowest priority - tasks that only run when system is idle
  idle(0);

  const TaskPriority(this.value);
  final int value;
}

/// Configuration for resource management
class TaskSchedulerConfig {
  /// Maximum number of concurrent tasks
  final int maxConcurrentTasks;
  
  /// Maximum CPU usage percentage (0.0 to 1.0)
  final double maxCpuUsage;
  
  /// Time slice duration for each task in milliseconds
  final int timeSliceMs;
  
  /// Minimum delay between task executions in milliseconds
  final int minTaskDelayMs;
  
  /// Whether to use adaptive scheduling based on system load
  final bool adaptiveScheduling;

  const TaskSchedulerConfig({
    this.maxConcurrentTasks = 2,
    this.maxCpuUsage = 0.7,
    this.timeSliceMs = 100,
    this.minTaskDelayMs = 10,
    this.adaptiveScheduling = true,
  });
  
  /// Default configuration for resource-constrained devices
  static const TaskSchedulerConfig resourceConstrained = TaskSchedulerConfig(
    maxConcurrentTasks: 1,
    maxCpuUsage: 0.5,
    timeSliceMs: 50,
    minTaskDelayMs: 20,
    adaptiveScheduling: true,
  );
  
  /// Default configuration for high-performance devices
  static const TaskSchedulerConfig highPerformance = TaskSchedulerConfig(
    maxConcurrentTasks: 4,
    maxCpuUsage: 0.8,
    timeSliceMs: 200,
    minTaskDelayMs: 5,
    adaptiveScheduling: true,
  );
}

/// Represents a scheduled task
class ScheduledTask {
  final String id;
  final String name;
  final TaskPriority priority;
  final Future<void> Function() task;
  final DateTime? scheduledTime;
  final Duration? interval;
  final int maxRetries;
  final Duration? timeout;
  
  int _retryCount = 0;
  DateTime? _lastExecution;
  bool _isRunning = false;
  
  ScheduledTask({
    required this.id,
    required this.name,
    required this.task,
    this.priority = TaskPriority.normal,
    this.scheduledTime,
    this.interval,
    this.maxRetries = 3,
    this.timeout,
  });
  
  /// Whether this is a recurring task
  bool get isRecurring => interval != null;
  
  /// Whether the task is currently running
  bool get isRunning => _isRunning;
  
  /// Number of retry attempts made
  int get retryCount => _retryCount;
  
  /// When the task was last executed
  DateTime? get lastExecution => _lastExecution;
  
  /// When the task should next run
  DateTime? get nextRunTime {
    if (scheduledTime != null && _lastExecution == null) {
      return scheduledTime;
    }
    if (isRecurring && _lastExecution != null) {
      return _lastExecution!.add(interval!);
    }
    return null;
  }
  
  /// Whether the task is ready to run
  bool get isReady {
    if (_isRunning) return false;
    final nextRun = nextRunTime;
    return nextRun == null || DateTime.now().isAfter(nextRun);
  }
  
  /// Whether the task has exceeded maximum retries
  bool get hasExceededRetries => _retryCount >= maxRetries;
}

/// Task execution result
class TaskExecutionResult {
  final ScheduledTask task;
  final bool success;
  final Duration executionTime;
  final Object? error;
  final StackTrace? stackTrace;
  
  const TaskExecutionResult({
    required this.task,
    required this.success,
    required this.executionTime,
    this.error,
    this.stackTrace,
  });
}

/// Callback for task execution events
typedef TaskExecutionCallback = void Function(TaskExecutionResult result);

/// Fair task scheduler for background operations
class TaskScheduler {
  static TaskScheduler? _instance;
  
  /// Get the singleton instance
  static TaskScheduler get instance {
    _instance ??= TaskScheduler._internal();
    return _instance!;
  }
  
  /// Reset the singleton (for testing)
  static void resetInstance() {
    _instance?._shutdown();
    _instance = null;
  }
  
  final TaskSchedulerConfig _config;
  final Queue<ScheduledTask> _taskQueue = Queue<ScheduledTask>();
  final Map<String, ScheduledTask> _tasks = <String, ScheduledTask>{};
  final Set<String> _runningTasks = <String>{};
  
  /// Semaphore for resource-constrained devices
  late final Semaphore _concurrencySemaphore;
  
  /// Database for storing task execution history
  DeclarativeDatabase? _database;
  
  Timer? _schedulerTimer;
  bool _isRunning = false;
  TaskExecutionCallback? _onTaskComplete;
  
  // Performance monitoring
  int _totalTasksExecuted = 0;
  int _totalTasksFailed = 0;
  Duration _totalExecutionTime = Duration.zero;
  
  TaskScheduler._internal([TaskSchedulerConfig? config]) 
    : _config = config ?? const TaskSchedulerConfig() {
    _concurrencySemaphore = Semaphore(_config.maxConcurrentTasks);
  }
  
  /// Initialize with custom configuration
  factory TaskScheduler.withConfig(TaskSchedulerConfig config) {
    _instance = TaskScheduler._internal(config);
    return _instance!;
  }
  
  /// Initialize with database for persistent task tracking
  void initializeWithDatabase(DeclarativeDatabase database) {
    _database = database;
    _ensureTaskHistoryTable();
  }
  
  /// Set callback for task completion events
  void setTaskExecutionCallback(TaskExecutionCallback callback) {
    _onTaskComplete = callback;
  }
  
  /// Start the scheduler
  void start() {
    if (_isRunning) return;
    
    _isRunning = true;
    _schedulerTimer = Timer.periodic(
      Duration(milliseconds: _config.timeSliceMs),
      (_) => _processTasks(),
    );
  }
  
  /// Stop the scheduler
  void stop() {
    _isRunning = false;
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
  }
  
  /// Schedule a one-time task
  String scheduleTask({
    required String name,
    required Future<void> Function() task,
    TaskPriority priority = TaskPriority.normal,
    DateTime? runAt,
    int maxRetries = 3,
    Duration? timeout,
  }) {
    final taskId = _generateTaskId();
    final scheduledTask = ScheduledTask(
      id: taskId,
      name: name,
      task: task,
      priority: priority,
      scheduledTime: runAt,
      maxRetries: maxRetries,
      timeout: timeout,
    );
    
    _addTask(scheduledTask);
    return taskId;
  }
  
  /// Schedule a recurring task with persistent tracking
  String scheduleRecurringTask({
    required String name,
    required Future<void> Function() task,
    required Duration interval,
    TaskPriority priority = TaskPriority.normal,
    DateTime? firstRun,
    int maxRetries = 3,
    Duration? timeout,
  }) {
    final taskId = _generateTaskId();
    
    // Check last run time from database if available
    DateTime? effectiveFirstRun = firstRun;
    if (_database != null && effectiveFirstRun == null) {
      effectiveFirstRun = _getNextRunTimeFromHistory(name, interval);
    }
    
    final scheduledTask = ScheduledTask(
      id: taskId,
      name: name,
      task: task,
      priority: priority,
      scheduledTime: firstRun,
      interval: interval,
      maxRetries: maxRetries,
      timeout: timeout,
    );
    
    _addTask(scheduledTask);
    return taskId;
  }
  
  /// Cancel a scheduled task
  bool cancelTask(String taskId) {
    final task = _tasks.remove(taskId);
    if (task != null) {
      _taskQueue.remove(task);
      return true;
    }
    return false;
  }
  
  /// Get task status
  ScheduledTask? getTask(String taskId) {
    return _tasks[taskId];
  }
  
  /// Get all scheduled tasks
  List<ScheduledTask> getAllTasks() {
    return _tasks.values.toList();
  }
  
  /// Get scheduler statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalTasksExecuted': _totalTasksExecuted,
      'totalTasksFailed': _totalTasksFailed,
      'averageExecutionTime': _totalTasksExecuted > 0 
        ? _totalExecutionTime.inMilliseconds / _totalTasksExecuted 
        : 0,
      'activeTasks': _taskQueue.length,
      'runningTasks': _runningTasks.length,
      'maxConcurrentTasks': _config.maxConcurrentTasks,
    };
  }
  
  void _addTask(ScheduledTask task) {
    _tasks[task.id] = task;
    _insertTaskByPriority(task);
    
    // Start scheduler if not running
    if (!_isRunning) {
      start();
    }
  }
  
  void _insertTaskByPriority(ScheduledTask task) {
    // Insert task in priority order (higher priority first)
    var inserted = false;
    final queue = _taskQueue.toList();
    _taskQueue.clear();
    
    for (var existingTask in queue) {
      if (!inserted && task.priority.value > existingTask.priority.value) {
        _taskQueue.add(task);
        inserted = true;
      }
      _taskQueue.add(existingTask);
    }
    
    if (!inserted) {
      _taskQueue.add(task);
    }
  }
  
  void _processTasks() {
    if (!_isRunning) return;
    
    // Check if we can run more tasks
    if (_runningTasks.length >= _config.maxConcurrentTasks) {
      return;
    }
    
    // Find next ready task
    final readyTasks = _taskQueue.where((task) => task.isReady).toList();
    if (readyTasks.isEmpty) {
      return;
    }
    
    // Sort by priority and next run time
    readyTasks.sort((a, b) {
      final priorityCompare = b.priority.value.compareTo(a.priority.value);
      if (priorityCompare != 0) return priorityCompare;
      
      final aNext = a.nextRunTime ?? DateTime.now();
      final bNext = b.nextRunTime ?? DateTime.now();
      return aNext.compareTo(bNext);
    });
    
    final task = readyTasks.first;
    _runTask(task);
  }
  
  void _runTask(ScheduledTask task) async {
    if (task._isRunning || _runningTasks.contains(task.id)) {
      return;
    }
    
    task._isRunning = true;
    _runningTasks.add(task.id);
    _taskQueue.remove(task);
    
    final startTime = DateTime.now();
    bool success = false;
    Object? error;
    StackTrace? stackTrace;
    
    try {
      // Apply timeout if specified
      if (task.timeout != null) {
        await task.task().timeout(task.timeout!);
      } else {
        await task.task();
      }
      success = true;
    } catch (e, st) {
      error = e;
      stackTrace = st;
      task._retryCount++;
    }
    
    final executionTime = DateTime.now().difference(startTime);
    task._lastExecution = DateTime.now();
    task._isRunning = false;
    _runningTasks.remove(task.id);
    
    // Update statistics
    _totalTasksExecuted++;
    _totalExecutionTime += executionTime;
    if (!success) {
      _totalTasksFailed++;
    }
    
    // Create execution result
    final result = TaskExecutionResult(
      task: task,
      success: success,
      executionTime: executionTime,
      error: error,
      stackTrace: stackTrace,
    );
    
    // Notify callback
    _onTaskComplete?.call(result);
    
    // Handle task completion
    if (success) {
      // Reset retry count on success
      task._retryCount = 0;
      
      // Reschedule if recurring
      if (task.isRecurring) {
        _insertTaskByPriority(task);
      } else {
        // Remove one-time completed task
        _tasks.remove(task.id);
      }
    } else {
      // Handle failure
      if (task.hasExceededRetries) {
        // Remove failed task
        _tasks.remove(task.id);
      } else {
        // Reschedule for retry with exponential backoff
        final delay = Duration(
          milliseconds: _config.minTaskDelayMs * pow(2, task._retryCount).toInt(),
        );
        Timer(delay, () {
          if (_tasks.containsKey(task.id)) {
            _insertTaskByPriority(task);
          }
        });
      }
    }
    
    // Add small delay to prevent overwhelming the system
    await Future.delayed(Duration(milliseconds: _config.minTaskDelayMs));
  }
  
  String _generateTaskId() {
    return 'task_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
  }
  
  void _shutdown() {
    stop();
    _taskQueue.clear();
    _tasks.clear();
    _runningTasks.clear();
  }
}