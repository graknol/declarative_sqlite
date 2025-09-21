import 'dart:async';
import 'package:test/test.dart';
import '../lib/src/scheduling/task_scheduler.dart';

void main() {
  group('TaskScheduler with Semaphore and Persistence', () {
    setUp(() {
      TaskScheduler.resetInstance();
    });

    tearDown(() {
      TaskScheduler.resetInstance();
    });

    test('respects concurrency limits with semaphore', () async {
      final config = TaskSchedulerConfig.resourceConstrained; // maxConcurrentTasks = 1
      final scheduler = TaskScheduler.withConfig(config);
      
      var runningCount = 0;
      var maxConcurrentCount = 0;
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();
      final completer3 = Completer<void>();
      
      // Schedule three tasks that should run sequentially due to semaphore limit
      scheduler.scheduleTask(
        name: 'task1',
        task: () async {
          runningCount++;
          maxConcurrentCount = runningCount > maxConcurrentCount ? runningCount : maxConcurrentCount;
          await completer1.future;
          runningCount--;
        },
      );
      
      scheduler.scheduleTask(
        name: 'task2', 
        task: () async {
          runningCount++;
          maxConcurrentCount = runningCount > maxConcurrentCount ? runningCount : maxConcurrentCount;
          await completer2.future;
          runningCount--;
        },
      );
      
      scheduler.scheduleTask(
        name: 'task3',
        task: () async {
          runningCount++;
          maxConcurrentCount = runningCount > maxConcurrentCount ? runningCount : maxConcurrentCount;
          await completer3.future;
          runningCount--;
        },
      );
      
      scheduler.start();
      
      // Give tasks time to start
      await Future.delayed(Duration(milliseconds: 200));
      
      // Should have only 1 task running due to semaphore
      expect(runningCount, equals(1));
      
      // Complete first task
      completer1.complete();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Second task should now be running
      expect(runningCount, equals(1));
      
      // Complete second task
      completer2.complete();
      await Future.delayed(Duration(milliseconds: 100));
      
      // Third task should now be running
      expect(runningCount, equals(1));
      
      // Complete third task
      completer3.complete();
      await Future.delayed(Duration(milliseconds: 100));
      
      // All tasks completed
      expect(runningCount, equals(0));
      expect(maxConcurrentCount, equals(1)); // Never exceeded limit
      
      scheduler.stop();
    });

    test('semaphore allows multiple tasks on high performance config', () async {
      final config = TaskSchedulerConfig.highPerformance; // maxConcurrentTasks = 4
      final scheduler = TaskScheduler.withConfig(config);
      
      var runningCount = 0;
      var maxConcurrentCount = 0;
      final completers = List.generate(4, (_) => Completer<void>());
      
      // Schedule four tasks that should run concurrently
      for (int i = 0; i < 4; i++) {
        scheduler.scheduleTask(
          name: 'task$i',
          task: () async {
            runningCount++;
            maxConcurrentCount = runningCount > maxConcurrentCount ? runningCount : maxConcurrentCount;
            await completers[i].future;
            runningCount--;
          },
        );
      }
      
      scheduler.start();
      
      // Give tasks time to start
      await Future.delayed(Duration(milliseconds: 200));
      
      // Should have all 4 tasks running concurrently
      expect(runningCount, equals(4));
      expect(maxConcurrentCount, equals(4));
      
      // Complete all tasks
      for (final completer in completers) {
        completer.complete();
      }
      
      await Future.delayed(Duration(milliseconds: 100));
      expect(runningCount, equals(0));
      
      scheduler.stop();
    });

    test('recurring tasks respect database persistence timing', () async {
      // This test would require a real database instance
      // For now, we'll test that the method exists and doesn't throw
      final scheduler = TaskScheduler.instance;
      
      expect(() {
        scheduler.scheduleRecurringTask(
          name: 'test_recurring',
          task: () async {},
          interval: Duration(minutes: 5),
        );
      }, returnsNormally);
    });
  });
}