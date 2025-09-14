import 'dart:async';
import 'package:meta/meta.dart';
import 'data_access.dart';
import 'lww_types.dart';

/// Server sync configuration options
@immutable
class ServerSyncOptions {
  const ServerSyncOptions({
    this.retryAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(minutes: 5),
    this.batchSize = 50,
    this.syncInterval = const Duration(minutes: 5),
  });

  /// Number of retry attempts for failed uploads (default: 3)
  final int retryAttempts;
  
  /// Initial delay between retry attempts (default: 2 seconds)
  final Duration retryDelay;
  
  /// Multiplier for exponential backoff (default: 2.0)
  final double backoffMultiplier;
  
  /// Maximum delay between retries (default: 5 minutes)
  final Duration maxDelay;
  
  /// Number of operations to upload in each batch (default: 50)
  final int batchSize;
  
  /// Interval for automatic sync attempts (default: 5 minutes)
  final Duration syncInterval;
}

/// Result of a server sync attempt
@immutable
class SyncResult {
  const SyncResult({
    required this.success,
    required this.syncedOperations,
    required this.failedOperations,
    this.discardedOperations = const [],
    this.error,
  });

  /// Whether the sync attempt was successful
  final bool success;
  
  /// List of operation IDs that were successfully synced
  final List<String> syncedOperations;
  
  /// List of operation IDs that failed to sync (will retry)
  final List<String> failedOperations;
  
  /// List of operation IDs that were discarded (permanent failures)
  final List<String> discardedOperations;
  
  /// Error message if sync failed
  final String? error;

  /// Total number of operations processed
  int get totalOperations => syncedOperations.length + failedOperations.length + discardedOperations.length;
  
  /// Whether all operations were successfully synced
  bool get isComplete => failedOperations.isEmpty && discardedOperations.isEmpty;
}

/// Callback function type for uploading operations to server
/// 
/// [operations] List of operations to upload
/// Returns true if upload was successful, false if permanent failure (400 error - should discard)
/// Should throw an exception for temporary failures that should be retried
typedef ServerUploadCallback = Future<bool> Function(List<PendingOperation> operations);

/// Callback function type for sync status updates
typedef SyncStatusCallback = void Function(SyncResult result);

/// Represents a single sync event in the timeline
@immutable
class SyncEvent {
  const SyncEvent({
    required this.timestamp,
    required this.type,
    required this.success,
    this.operationCount = 0,
    this.syncedCount = 0,
    this.failedCount = 0,
    this.discardedCount = 0,
    this.error,
  });

  /// When this sync event occurred
  final DateTime timestamp;
  
  /// Type of sync event
  final SyncEventType type;
  
  /// Whether the sync was successful
  final bool success;
  
  /// Total number of operations involved
  final int operationCount;
  
  /// Number of operations successfully synced
  final int syncedCount;
  
  /// Number of operations that failed (will retry)
  final int failedCount;
  
  /// Number of operations discarded (permanent failures)
  final int discardedCount;
  
  /// Error message if sync failed
  final String? error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncEvent &&
          timestamp == other.timestamp &&
          type == other.type &&
          success == other.success &&
          operationCount == other.operationCount &&
          syncedCount == other.syncedCount &&
          failedCount == other.failedCount &&
          discardedCount == other.discardedCount &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
    timestamp, type, success, operationCount, 
    syncedCount, failedCount, discardedCount, error
  );

  @override
  String toString() => 'SyncEvent($type at $timestamp: ${success ? 'success' : 'failed'} - $syncedCount synced, $failedCount failed, $discardedCount discarded)';
}

/// Types of sync events
enum SyncEventType {
  /// Automatic sync triggered by timer
  automatic,
  /// Manual sync triggered by user
  manual,
  /// Sync triggered on app startup
  startup,
}

/// Manages sync history and timeline for debugging purposes
class SyncStatusHistory {
  static const int _maxHistorySize = 100;
  
  final List<SyncEvent> _events = [];
  DateTime? _lastSuccessfulSync;
  int _totalSynced = 0;
  int _totalFailed = 0;
  int _totalDiscarded = 0;

  /// Add a new sync event to the history
  void addEvent(SyncEvent event) {
    _events.add(event);
    
    // Update counters
    _totalSynced += event.syncedCount;
    _totalFailed += event.failedCount;
    _totalDiscarded += event.discardedCount;
    
    // Update last successful sync time
    if (event.success && event.syncedCount > 0) {
      _lastSuccessfulSync = event.timestamp;
    }
    
    // Keep history size manageable
    if (_events.length > _maxHistorySize) {
      _events.removeAt(0);
    }
  }

  /// Get all sync events in chronological order (most recent first)
  List<SyncEvent> get events => List.unmodifiable(_events.reversed);

  /// Get the timestamp of the last successful sync
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;

  /// Get total number of operations synced successfully
  int get totalSynced => _totalSynced;

  /// Get total number of operations that failed
  int get totalFailed => _totalFailed;

  /// Get total number of operations discarded (permanent failures)
  int get totalDiscarded => _totalDiscarded;

  /// Get events from the last N minutes
  List<SyncEvent> getRecentEvents([int minutes = 60]) {
    final cutoff = DateTime.now().subtract(Duration(minutes: minutes));
    return _events.where((event) => event.timestamp.isAfter(cutoff)).toList().reversed.toList();
  }

  /// Clear all history
  void clear() {
    _events.clear();
    _lastSuccessfulSync = null;
    _totalSynced = 0;
    _totalFailed = 0;
    _totalDiscarded = 0;
  }
}

/// Wrapper class that handles automatic server synchronization with retry logic
/// 
/// Provides a simple interface for developers to upload LWW data to the server
/// without having to implement timing logic, retry handling, or exception management.
/// 
/// Usage:
/// ```dart
/// final syncManager = ServerSyncManager(
///   dataAccess: dataAccess,
///   uploadCallback: (operations) async {
///     // Your server upload logic here
///     return await myServerApi.uploadOperations(operations);
///   },
/// );
/// 
/// // Start automatic sync
/// await syncManager.startAutoSync();
/// 
/// // Or sync manually
/// final result = await syncManager.syncNow();
/// ```
class ServerSyncManager {
  ServerSyncManager({
    required this.dataAccess,
    required this.uploadCallback,
    this.onSyncStatus,
    this.options = const ServerSyncOptions(),
  }) : _syncHistory = SyncStatusHistory();

  /// The data access instance to sync from (must have LWW support enabled)
  final DataAccess dataAccess;
  
  /// Callback function for uploading operations to server
  final ServerUploadCallback uploadCallback;
  
  /// Optional callback for sync status updates
  final SyncStatusCallback? onSyncStatus;
  
  /// Configuration options for sync behavior
  final ServerSyncOptions options;

  /// Sync history tracker for debugging and timeline
  final SyncStatusHistory _syncHistory;

  Timer? _autoSyncTimer;
  bool _syncInProgress = false;
  bool _autoSyncEnabled = false;

  /// Starts automatic synchronization at the configured interval
  Future<void> startAutoSync() async {
    if (_autoSyncEnabled) {
      return; // Already started
    }

    _autoSyncEnabled = true;
    
    // Do an initial sync
    await _performSyncWithHistory(SyncEventType.startup);
    
    // Schedule periodic sync
    _autoSyncTimer = Timer.periodic(options.syncInterval, (_) async {
      if (!_syncInProgress && _autoSyncEnabled) {
        await _performSyncWithHistory(SyncEventType.automatic);
      }
    });
  }

  /// Stops automatic synchronization
  void stopAutoSync() {
    _autoSyncEnabled = false;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Performs an immediate synchronization attempt
  /// Returns the result of the sync operation
  Future<SyncResult> syncNow() async {
    if (_syncInProgress) {
      throw StateError('Sync already in progress');
    }

    _syncInProgress = true;
    try {
      return await _performSyncWithHistory(SyncEventType.manual);
    } finally {
      _syncInProgress = false;
    }
  }

  /// Internal wrapper that adds sync history tracking
  Future<SyncResult> _performSyncWithHistory(SyncEventType eventType) async {
    final result = await _performSync();
    
    // Add event to history
    _syncHistory.addEvent(SyncEvent(
      timestamp: DateTime.now(),
      type: eventType,
      success: result.success,
      operationCount: result.totalOperations,
      syncedCount: result.syncedOperations.length,
      failedCount: result.failedOperations.length,
      discardedCount: result.discardedOperations.length,
      error: result.error,
    ));
    
    return result;
  }

  /// Whether auto-sync is currently enabled
  bool get isAutoSyncEnabled => _autoSyncEnabled;
  
  /// Whether a sync operation is currently in progress
  bool get isSyncInProgress => _syncInProgress;

  /// Get sync history for debugging and timeline display
  SyncStatusHistory get syncHistory => _syncHistory;

  /// Get the timestamp of the last successful sync
  DateTime? get lastSuccessfulSync => _syncHistory.lastSuccessfulSync;

  /// Get the current number of pending operations
  int get pendingOperationsCount => dataAccess.getPendingOperations().length;

  /// Internal method that performs the actual sync with retry logic
  Future<SyncResult> _performSync() async {
    final pendingOperations = dataAccess.getPendingOperations();
    
    if (pendingOperations.isEmpty) {
      final result = SyncResult(
        success: true,
        syncedOperations: const [],
        failedOperations: const [],
        discardedOperations: const [],
      );
      onSyncStatus?.call(result);
      return result;
    }

    final syncedOperations = <String>[];
    final failedOperations = <String>[];
    final discardedOperations = <String>[];
    String? lastError;

    // Process operations in batches
    for (int i = 0; i < pendingOperations.length; i += options.batchSize) {
      final endIndex = (i + options.batchSize < pendingOperations.length) 
          ? i + options.batchSize 
          : pendingOperations.length;
      final batch = pendingOperations.sublist(i, endIndex);

      try {
        final uploadResult = await _uploadBatchWithRetry(batch);
        if (uploadResult == true) {
          // Mark operations as synced
          for (final operation in batch) {
            dataAccess.markOperationSynced(operation.id);
            syncedOperations.add(operation.id);
          }
        } else if (uploadResult == false) {
          // Permanent failure - discard operations
          for (final operation in batch) {
            dataAccess.discardOperation(operation.id);
            discardedOperations.add(operation.id);
          }
          lastError = 'Operations discarded due to permanent failure (e.g., 400 error)';
        } else {
          // This shouldn't happen with bool return type, but handle gracefully
          for (final operation in batch) {
            failedOperations.add(operation.id);
          }
          lastError = 'Upload failed after all retry attempts';
        }
      } catch (e) {
        // Temporary failure - add to failed operations for retry
        for (final operation in batch) {
          failedOperations.add(operation.id);
        }
        lastError = e.toString();
      }
    }

    // Clean up successfully synced and discarded operations
    if (syncedOperations.isNotEmpty) {
      dataAccess.clearSyncedOperations();
    }

    final result = SyncResult(
      success: failedOperations.isEmpty && discardedOperations.isEmpty,
      syncedOperations: syncedOperations,
      failedOperations: failedOperations,
      discardedOperations: discardedOperations,
      error: lastError,
    );

    onSyncStatus?.call(result);
    return result;
  }

  /// Uploads a batch of operations with retry logic and exponential backoff
  Future<bool> _uploadBatchWithRetry(List<PendingOperation> batch) async {
    Duration currentDelay = options.retryDelay;
    
    for (int attempt = 0; attempt <= options.retryAttempts; attempt++) {
      try {
        final success = await uploadCallback(batch);
        if (success) {
          return true;
        } else {
          // Callback returned false - this is a permanent failure, don't retry
          return false;
        }
      } catch (e) {
        // If it's the last attempt or a permanent error, rethrow
        if (attempt == options.retryAttempts || _isPermanentError(e)) {
          rethrow;
        }
        
        // Wait before retrying
        await Future.delayed(currentDelay);
        currentDelay = Duration(
          milliseconds: (currentDelay.inMilliseconds * options.backoffMultiplier).round()
        );
        if (currentDelay > options.maxDelay) {
          currentDelay = options.maxDelay;
        }
      }
    }
    
    return false;
  }

  /// Determines if an error is permanent and should not be retried
  bool _isPermanentError(dynamic error) {
    // This can be customized based on specific error types
    final errorString = error.toString().toLowerCase();
    
    // Common permanent error indicators
    return errorString.contains('unauthorized') ||
           errorString.contains('forbidden') ||
           errorString.contains('bad request') ||
           errorString.contains('not found') ||
           errorString.contains('conflict');
  }

  /// Disposes resources and stops auto-sync
  void dispose() {
    stopAutoSync();
  }
}