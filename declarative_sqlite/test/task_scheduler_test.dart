import 'package:test/test.dart';
import 'package:declarative_sqlite/src/scheduling/task_scheduler.dart';

void main() {
  group('TaskScheduler', () {
    late TaskScheduler scheduler;
    
    setUp(() {
      TaskScheduler.resetInstance();
      scheduler = TaskScheduler.instance;
    });
    
    tearDown(() {
      scheduler.stop();
      TaskScheduler.resetInstance();
    });
    
    test('should be singleton', () {
      final scheduler1 = TaskScheduler.instance;
      final scheduler2 = TaskScheduler.instance;
      expect(scheduler1, same(scheduler2));
    });
    
    test('should schedule and execute one-time task', () async {
      var executed = false;
      
      final taskId = scheduler.scheduleTask(
        name: 'Test Task',
        task: () async {
          executed = true;
        },
      );
      
      scheduler.start();
      
      // Wait for task execution
      await Future.delayed(const Duration(milliseconds: 200));
      
      expect(executed, isTrue);
      expect(scheduler.getTask(taskId), isNull); // Should be removed after completion
    });
    
    test('should schedule and execute recurring task', () async {
      var executionCount = 0;
      
      final taskId = scheduler.scheduleRecurringTask(
        name: 'Recurring Task',
        task: () async {
          executionCount++;
        },
        interval: const Duration(milliseconds: 50),
      );
      
      scheduler.start();
      
      // Wait for multiple executions
      await Future.delayed(const Duration(milliseconds: 200));
      
      expect(executionCount, greaterThan(1));
      expect(scheduler.getTask(taskId), isNotNull); // Should still exist
      
      scheduler.cancelTask(taskId);
    });
    
    test('should respect task priorities', () async {
      final executionOrder = <String>[];
      
      // Schedule low priority task first
      scheduler.scheduleTask(
        name: 'Low Priority',
        task: () async {
          executionOrder.add('low');
        },
        priority: TaskPriority.low,
      );
      
      // Schedule high priority task after
      scheduler.scheduleTask(
        name: 'High Priority',
        task: () async {
          executionOrder.add('high');
        },
        priority: TaskPriority.high,
      );
      
      scheduler.start();
      
      // Wait for both tasks to execute
      await Future.delayed(const Duration(milliseconds: 200));
      
      expect(executionOrder.first, equals('high'));
      expect(executionOrder.length, equals(2));
    });
    
    test('should handle task failures and retries', () async {
      var attemptCount = 0;
      
      scheduler.scheduleTask(
        name: 'Failing Task',
        task: () async {
          attemptCount++;
          if (attemptCount < 3) {
            throw Exception('Task failed');
          }
        },
        maxRetries: 3,
      );
      
      scheduler.start();
      
      // Wait for retries
      await Future.delayed(const Duration(seconds: 1));
      
      expect(attemptCount, equals(3));
    });
    
    test('should respect concurrent task limits', () async {
      const config = TaskSchedulerConfig(maxConcurrentTasks: 1);
      TaskScheduler.resetInstance();
      scheduler = TaskScheduler.withConfig(config);
      
      var runningTasks = 0;
      var maxConcurrent = 0;
      
      // Schedule multiple long-running tasks
      for (int i = 0; i < 3; i++) {
        scheduler.scheduleTask(
          name: 'Long Task $i',
          task: () async {
            runningTasks++;
            maxConcurrent = runningTasks > maxConcurrent ? runningTasks : maxConcurrent;
            await Future.delayed(const Duration(milliseconds: 100));
            runningTasks--;
          },
        );
      }
      
      scheduler.start();
      
      // Wait for all tasks to complete
      await Future.delayed(const Duration(milliseconds: 500));
      
      expect(maxConcurrent, equals(1));
    });
    
    test('should cancel scheduled tasks', () async {
      var executed = false;
      
      final taskId = scheduler.scheduleTask(
        name: 'Cancelable Task',
        task: () async {
          executed = true;
        },
        runAt: DateTime.now().add(const Duration(milliseconds: 100)),
      );
      
      final cancelled = scheduler.cancelTask(taskId);
      scheduler.start();
      
      // Wait longer than the scheduled time
      await Future.delayed(const Duration(milliseconds: 200));
      
      expect(cancelled, isTrue);
      expect(executed, isFalse);
    });
    
    test('should provide accurate statistics', () async {
      // Schedule and execute a task
      scheduler.scheduleTask(
        name: 'Stats Task',
        task: () async {
          await Future.delayed(const Duration(milliseconds: 10));
        },
      );
      
      scheduler.start();
      
      // Wait for execution
      await Future.delayed(const Duration(milliseconds: 100));
      
      final stats = scheduler.getStatistics();
      expect(stats['totalTasksExecuted'], equals(1));
      expect(stats['totalTasksFailed'], equals(0));
      expect(stats['averageExecutionTime'], greaterThan(0));
    });
    
    test('should handle task timeouts', () async {
      var timedOut = false;
      
      scheduler.setTaskExecutionCallback((result) {
        if (!result.success && result.error is TimeoutException) {
          timedOut = true;
        }
      });
      
      scheduler.scheduleTask(
        name: 'Timeout Task',
        task: () async {
          await Future.delayed(const Duration(milliseconds: 200));
        },
        timeout: const Duration(milliseconds: 50),
      );
      
      scheduler.start();
      
      // Wait for timeout
      await Future.delayed(const Duration(milliseconds: 300));
      
      expect(timedOut, isTrue);
    });
    
    test('should handle scheduled tasks correctly', () async {
      var executed = false;
      final scheduledTime = DateTime.now().add(const Duration(milliseconds: 100));
      
      scheduler.scheduleTask(
        name: 'Scheduled Task',
        task: () async {
          executed = true;
        },
        runAt: scheduledTime,
      );
      
      scheduler.start();
      
      // Should not execute immediately
      await Future.delayed(const Duration(milliseconds: 50));
      expect(executed, isFalse);
      
      // Should execute after scheduled time
      await Future.delayed(const Duration(milliseconds: 100));
      expect(executed, isTrue);
    });
  });
  
  group('TaskSchedulerConfig', () {
    test('should have correct default values', () {
      const config = TaskSchedulerConfig();
      expect(config.maxConcurrentTasks, equals(2));
      expect(config.maxCpuUsage, equals(0.7));
      expect(config.timeSliceMs, equals(100));
      expect(config.minTaskDelayMs, equals(10));
      expect(config.adaptiveScheduling, isTrue);
    });
    
    test('should have resource constrained preset', () {
      const config = TaskSchedulerConfig.resourceConstrained;
      expect(config.maxConcurrentTasks, equals(1));
      expect(config.maxCpuUsage, equals(0.5));
      expect(config.timeSliceMs, equals(50));
    });
    
    test('should have high performance preset', () {
      const config = TaskSchedulerConfig.highPerformance;
      expect(config.maxConcurrentTasks, equals(4));
      expect(config.maxCpuUsage, equals(0.8));
      expect(config.timeSliceMs, equals(200));
    });
  });
  
  group('ScheduledTask', () {
    test('should track execution state correctly', () {
      final task = ScheduledTask(
        id: 'test',
        name: 'Test Task',
        task: () async {},
      );
      
      expect(task.isReady, isTrue);
      expect(task.isRunning, isFalse);
      expect(task.retryCount, equals(0));
      expect(task.lastExecution, isNull);
    });
    
    test('should calculate next run time for recurring tasks', () {
      final now = DateTime.now();
      final task = ScheduledTask(
        id: 'test',
        name: 'Recurring Task',
        task: () async {},
        interval: const Duration(minutes: 5),
      );
      
      // Simulate execution
      task._lastExecution = now;
      
      final nextRun = task.nextRunTime;
      expect(nextRun, isNotNull);
      expect(nextRun!.isAfter(now), isTrue);
      expect(nextRun.difference(now).inMinutes, equals(5));
    });
    
    test('should handle scheduled time correctly', () {
      final scheduledTime = DateTime.now().add(const Duration(minutes: 1));
      final task = ScheduledTask(
        id: 'test',
        name: 'Scheduled Task',
        task: () async {},
        scheduledTime: scheduledTime,
      );
      
      expect(task.nextRunTime, equals(scheduledTime));
      expect(task.isReady, isFalse); // Should not be ready until scheduled time
    });
  });
}