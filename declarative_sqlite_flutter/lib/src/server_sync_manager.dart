import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:flutter/widgets.dart';
import 'database_provider.dart';

/// A widget that manages server synchronization using TaskScheduler.
/// 
/// This widget registers sync operations with the TaskScheduler for better
/// resource management and fair scheduling with other background tasks.
/// 
/// Example:
/// ```dart
/// ServerSyncManagerWidget(
///   retryStrategy: ExponentialBackoffRetry(),
///   syncInterval: Duration(minutes: 5),
///   onFetch: (database, tableTimestamps) async {
///     // Fetch data from server using delta timestamps
///   },
///   onSend: (operations) async {
///     // Send changes to server
///     return true; // Success
///   },
///   child: MyApp(),
/// )
/// ```
class ServerSyncManagerWidget extends StatefulWidget {
  final dynamic retryStrategy;
  final Duration syncInterval;
  final OnFetch onFetch;
  final OnSend onSend;
  final Widget child;
  final DeclarativeDatabase? database;
  final TaskScheduler? taskScheduler;

  const ServerSyncManagerWidget({
    super.key,
    required this.retryStrategy,
    this.syncInterval = const Duration(minutes: 5),
    required this.onFetch,
    required this.onSend,
    required this.child,
    this.database,
    this.taskScheduler,
  });

  @override
  State<ServerSyncManagerWidget> createState() => _ServerSyncManagerWidgetState();
}

class _ServerSyncManagerWidgetState extends State<ServerSyncManagerWidget> {
  ServerSyncManager? _syncManager;
  TaskScheduler? _scheduler;
  String? _syncTaskName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSyncManager();
    });
  }

  @override
  void didUpdateWidget(ServerSyncManagerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If configuration changed, restart sync manager
    if (_shouldRestartSyncManager(oldWidget)) {
      _disposeSyncManager();
      _initializeSyncManager();
    }
  }

  bool _shouldRestartSyncManager(ServerSyncManagerWidget oldWidget) {
    return widget.syncInterval != oldWidget.syncInterval ||
        widget.onFetch != oldWidget.onFetch ||
        widget.onSend != oldWidget.onSend ||
        widget.database != oldWidget.database ||
        widget.taskScheduler != oldWidget.taskScheduler;
  }

  @override
  void dispose() {
    _disposeSyncManager();
    super.dispose();
  }

  void _initializeSyncManager() {
    final database = _getDatabaseInstance();
    
    if (database == null) {
      // No database available, can't initialize sync
      return;
    }

    try {
      _createSyncManagerAndScheduleTask(database);
    } catch (error) {
      _handleSyncManagerError(error);
    }
  }

  DeclarativeDatabase? _getDatabaseInstance() {
    return widget.database ?? DatabaseProvider.maybeOf(context);
  }

  void _createSyncManagerAndScheduleTask(DeclarativeDatabase database) {
    // Create sync manager without internal timer
    _syncManager = ServerSyncManager(
      db: database,
      retryStrategy: widget.retryStrategy,
      onFetch: widget.onFetch,
      onSend: widget.onSend,
    );

    // Get or create task scheduler
    _scheduler = widget.taskScheduler ?? TaskScheduler.withConfig(
      TaskSchedulerConfig.autoDetectDevice()
    );

    // Initialize scheduler with database for persistent tracking
    _scheduler!.initializeWithDatabase(database);

    // Schedule recurring sync task
    _syncTaskName = 'server_sync_${database.hashCode}';
    _scheduler!.scheduleRecurringTask(
      name: _syncTaskName!,
      task: () => _syncManager!.performSync(),
      interval: widget.syncInterval,
      priority: TaskPriority.normal,
    );

    // Perform initial sync
    _syncManager!.performSync();
  }

  void _handleSyncManagerError(Object error) {
    debugPrint('Failed to initialize ServerSyncManager: $error');
  }

  void _disposeSyncManager() {
    if (_syncTaskName != null && _scheduler != null) {
      _scheduler!.cancelTask(_syncTaskName!);
    }
    _syncManager = null;
    _scheduler = null;
    _syncTaskName = null;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
