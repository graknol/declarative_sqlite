import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test/test.dart';
import 'dart:math' as math;

void main() {
  group('TaskScheduler Comprehensive Tests', () {
    late TaskScheduler scheduler;
    late DeclarativeDatabase db;

    setUp(() async {
      final schema = SchemaBuilder()
        ..table('tasks', (table) {
          table.text('id').notNull('');
          table.text('name').notNull('');
          table.key(['id']).primary();
        })
        ..build();
      
      db = await DeclarativeDatabase.openInMemory('test', schema: schema);
      scheduler = TaskScheduler.withConfig(TaskSchedulerConfig.resourceConstrained);
      await scheduler.initializeWithDatabase(db);
    });

    tearDown(() async {
      await scheduler.shutdown();
      await db.close();
    });

    test('semaphore enforces concurrency limits on resource-constrained devices', () async {
      int runningTasks = 0;
      int maxConcurrentTasks = 0;
      
      final tasks = <Future>[];
      
      for (int i = 0; i < 5; i++) {
        tasks.add(scheduler.scheduleOneTimeTask(
          name: 'task_$i',
          task: () async {
            runningTasks++;
            maxConcurrentTasks = math.max(maxConcurrentTasks, runningTasks);
            await Future.delayed(Duration(milliseconds: 100));
            runningTasks--;
          },
          priority: TaskPriority.normal,
        ));
      }
      
      await Future.wait(tasks);
      
      // Resource-constrained should only allow 1 concurrent task
      expect(maxConcurrentTasks, equals(1));
    });

    test('tasks store execution history in database', () async {
      await scheduler.scheduleOneTimeTask(
        name: 'test_task',
        task: () async {
          await Future.delayed(Duration(milliseconds: 50));
        },
        priority: TaskPriority.normal,
      );

      // Check that execution was recorded
      final history = await db.query((q) => q.from('task_execution_history')
                                           .where(col('task_name').eq('test_task')));
      
      expect(history.length, equals(1));
      expect(history.first.getValue<String>('task_name'), equals('test_task'));
      expect(history.first.getValue<bool>('success'), isTrue);
      expect(history.first.getValue<DateTime>('executed_at'), isA<DateTime>());
    });

    test('recurring tasks resume proper timing after restart', () async {
      final executionTimes = <DateTime>[];
      
      // Schedule recurring task
      scheduler.scheduleRecurringTask(
        name: 'recurring_test',
        task: () async {
          executionTimes.add(DateTime.now());
        },
        interval: Duration(milliseconds: 200),
        priority: TaskPriority.normal,
      );

      // Wait for a couple executions
      await Future.delayed(Duration(milliseconds: 500));
      
      expect(executionTimes.length, greaterThanOrEqualTo(2));
      
      // Verify interval is roughly correct
      if (executionTimes.length >= 2) {
        final interval = executionTimes[1].difference(executionTimes[0]);
        expect(interval.inMilliseconds, greaterThan(150));
        expect(interval.inMilliseconds, lessThan(300));
      }
    });

    test('priority-based scheduling works correctly', () async {
      final executionOrder = <String>[];
      
      // Schedule tasks with different priorities
      scheduler.scheduleOneTimeTask(
        name: 'low_priority',
        task: () async {
          executionOrder.add('low_priority');
        },
        priority: TaskPriority.low,
      );
      
      scheduler.scheduleOneTimeTask(
        name: 'high_priority',
        task: () async {
          executionOrder.add('high_priority');
        },
        priority: TaskPriority.high,
      );
      
      scheduler.scheduleOneTimeTask(
        name: 'critical_priority',
        task: () async {
          executionOrder.add('critical_priority');
        },
        priority: TaskPriority.critical,
      );

      await Future.delayed(Duration(milliseconds: 300));
      
      // Higher priority tasks should execute first
      expect(executionOrder.first, equals('critical_priority'));
      expect(executionOrder.contains('high_priority'), isTrue);
      expect(executionOrder.contains('low_priority'), isTrue);
    });

    test('task retry logic works on failures', () async {
      int attemptCount = 0;
      
      await scheduler.scheduleOneTimeTask(
        name: 'failing_task',
        task: () async {
          attemptCount++;
          if (attemptCount < 3) {
            throw Exception('Task failed');
          }
        },
        priority: TaskPriority.normal,
        maxRetries: 3,
        retryDelay: Duration(milliseconds: 50),
      );

      expect(attemptCount, equals(3));
      
      // Check that all attempts were recorded
      final history = await db.query((q) => q.from('task_execution_history')
                                           .where(col('task_name').eq('failing_task')));
      
      expect(history.length, equals(3));
      expect(history.take(2).every((r) => r.getValue<bool>('success') == false), isTrue);
      expect(history.last.getValue<bool>('success'), isTrue);
    });

    test('device-specific configurations work correctly', () {
      final resourceConstrained = TaskScheduler.withConfig(TaskSchedulerConfig.resourceConstrained);
      final highPerformance = TaskScheduler.withConfig(TaskSchedulerConfig.highPerformance);
      
      expect(resourceConstrained.config.maxConcurrentTasks, equals(1));
      expect(highPerformance.config.maxConcurrentTasks, equals(4));
      
      resourceConstrained.shutdown();
      highPerformance.shutdown();
    });

    test('DatabaseMaintenanceTasks integration works', () async {
      bool garbageCollectionRan = false;
      bool syncRan = false;
      
      // Schedule maintenance tasks
      DatabaseMaintenanceTasks.scheduleFilesetGarbageCollection(
        garbageCollectTask: () async {
          garbageCollectionRan = true;
          return {'filesets': 0, 'files': 0};
        },
        interval: Duration(milliseconds: 100),
        scheduler: scheduler,
      );
      
      DatabaseMaintenanceTasks.scheduleSyncOperation(
        syncManager: MockSyncManager(() async { syncRan = true; }),
        interval: Duration(milliseconds: 150),
        scheduler: scheduler,
      );

      await Future.delayed(Duration(milliseconds: 300));
      
      expect(garbageCollectionRan, isTrue);
      expect(syncRan, isTrue);
    });
  });
}

class MockSyncManager {
  final Future<void> Function() onSync;
  
  MockSyncManager(this.onSync);
  
  Future<void> performSync() => onSync();
}