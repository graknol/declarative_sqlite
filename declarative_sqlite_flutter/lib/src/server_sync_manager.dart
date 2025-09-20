import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:flutter/widgets.dart';
import 'database_provider.dart';

/// A widget that manages server synchronization for a declarative_sqlite database.
/// 
/// This widget automatically starts and stops sync operations based on the widget
/// lifecycle and provides sync state to its descendants.
/// 
/// Example:
/// ```dart
/// ServerSyncManagerWidget(
///   retryStrategy: ExponentialBackoffRetry(),
///   fetchInterval: Duration(minutes: 5),
///   onFetch: (database, table, lastSynced) async {
///     // Fetch data from server
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
  final Duration fetchInterval;
  final OnFetch onFetch;
  final OnSend onSend;
  final Widget child;
  final DeclarativeDatabase? database;

  const ServerSyncManagerWidget({
    super.key,
    required this.retryStrategy,
    required this.fetchInterval,
    required this.onFetch,
    required this.onSend,
    required this.child,
    this.database,
  });

  @override
  State<ServerSyncManagerWidget> createState() => _ServerSyncManagerWidgetState();
}

class _ServerSyncManagerWidgetState extends State<ServerSyncManagerWidget> {
  ServerSyncManager? _syncManager;

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
    return widget.fetchInterval != oldWidget.fetchInterval ||
        widget.onFetch != oldWidget.onFetch ||
        widget.onSend != oldWidget.onSend ||
        widget.database != oldWidget.database;
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
      _createAndStartSyncManager(database);
    } catch (error) {
      _handleSyncManagerError(error);
    }
  }

  DeclarativeDatabase? _getDatabaseInstance() {
    return widget.database ?? DatabaseProvider.maybeOf(context);
  }

  void _createAndStartSyncManager(DeclarativeDatabase database) {
    _syncManager = ServerSyncManager(
      db: database,
      retryStrategy: widget.retryStrategy,
      fetchInterval: widget.fetchInterval,
      onFetch: widget.onFetch,
      onSend: widget.onSend,
    );
    
    _syncManager?.start();
  }

  void _handleSyncManagerError(Object error) {
    debugPrint('Failed to initialize ServerSyncManager: $error');
  }

  void _disposeSyncManager() {
    _syncManager?.stop();
    _syncManager = null;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
