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
    this.error,
  });

  /// Whether the sync attempt was successful
  final bool success;
  
  /// List of operation IDs that were successfully synced
  final List<String> syncedOperations;
  
  /// List of operation IDs that failed to sync
  final List<String> failedOperations;
  
  /// Error message if sync failed
  final String? error;

  /// Total number of operations processed
  int get totalOperations => syncedOperations.length + failedOperations.length;
  
  /// Whether all operations were successfully synced
  bool get isComplete => failedOperations.isEmpty;
}

/// Callback function type for uploading operations to server
/// 
/// [operations] List of operations to upload
/// Returns true if upload was successful, false otherwise
/// Should throw an exception if there's a permanent failure
typedef ServerUploadCallback = Future<bool> Function(List<PendingOperation> operations);

/// Callback function type for sync status updates
typedef SyncStatusCallback = void Function(SyncResult result);

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
  });

  /// The data access instance to sync from (must have LWW support enabled)
  final DataAccess dataAccess;
  
  /// Callback function for uploading operations to server
  final ServerUploadCallback uploadCallback;
  
  /// Optional callback for sync status updates
  final SyncStatusCallback? onSyncStatus;
  
  /// Configuration options for sync behavior
  final ServerSyncOptions options;

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
    await syncNow();
    
    // Schedule periodic sync
    _autoSyncTimer = Timer.periodic(options.syncInterval, (_) async {
      if (!_syncInProgress && _autoSyncEnabled) {
        await syncNow();
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
      return await _performSync();
    } finally {
      _syncInProgress = false;
    }
  }

  /// Whether auto-sync is currently enabled
  bool get isAutoSyncEnabled => _autoSyncEnabled;
  
  /// Whether a sync operation is currently in progress
  bool get isSyncInProgress => _syncInProgress;

  /// Internal method that performs the actual sync with retry logic
  Future<SyncResult> _performSync() async {
    final pendingOperations = dataAccess.getPendingOperations();
    
    if (pendingOperations.isEmpty) {
      final result = SyncResult(
        success: true,
        syncedOperations: const [],
        failedOperations: const [],
      );
      onSyncStatus?.call(result);
      return result;
    }

    final syncedOperations = <String>[];
    final failedOperations = <String>[];
    String? lastError;

    // Process operations in batches
    for (int i = 0; i < pendingOperations.length; i += options.batchSize) {
      final endIndex = (i + options.batchSize < pendingOperations.length) 
          ? i + options.batchSize 
          : pendingOperations.length;
      final batch = pendingOperations.sublist(i, endIndex);

      try {
        final success = await _uploadBatchWithRetry(batch);
        if (success) {
          // Mark operations as synced
          for (final operation in batch) {
            dataAccess.markOperationSynced(operation.id);
            syncedOperations.add(operation.id);
          }
        } else {
          // Add to failed operations
          for (final operation in batch) {
            failedOperations.add(operation.id);
          }
          lastError = 'Upload failed after all retry attempts';
        }
      } catch (e) {
        // Permanent failure - add to failed operations
        for (final operation in batch) {
          failedOperations.add(operation.id);
        }
        lastError = e.toString();
      }
    }

    // Clean up successfully synced operations
    if (syncedOperations.isNotEmpty) {
      dataAccess.clearSyncedOperations();
    }

    final result = SyncResult(
      success: failedOperations.isEmpty,
      syncedOperations: syncedOperations,
      failedOperations: failedOperations,
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
        }
        
        // If not the last attempt, wait before retrying
        if (attempt < options.retryAttempts) {
          await Future.delayed(currentDelay);
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * options.backoffMultiplier).round()
          );
          // Cap the delay at maxDelay
          if (currentDelay > options.maxDelay) {
            currentDelay = options.maxDelay;
          }
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