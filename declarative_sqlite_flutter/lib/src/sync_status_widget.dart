import 'dart:async';
import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// A widget that displays sync status information including a timeline of sync events
/// and current pending operations count.
class SyncStatusWidget extends StatefulWidget {
  const SyncStatusWidget({
    Key? key,
    required this.syncManager,
    this.refreshInterval = const Duration(seconds: 5),
    this.maxEventsToShow = 20,
    this.showPendingOperations = true,
    this.showSyncHistory = true,
    this.compact = false,
  }) : super(key: key);

  /// The sync manager to display status for
  final ServerSyncManager syncManager;
  
  /// How often to refresh the status display
  final Duration refreshInterval;
  
  /// Maximum number of sync events to show in the timeline
  final int maxEventsToShow;
  
  /// Whether to show the pending operations section
  final bool showPendingOperations;
  
  /// Whether to show the sync history timeline
  final bool showSyncHistory;
  
  /// Whether to use a compact layout
  final bool compact;

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactView();
    }
    
    return _buildFullView();
  }

  Widget _buildCompactView() {
    final pendingCount = widget.syncManager.pendingOperationsCount;
    final lastSync = widget.syncManager.lastSuccessfulSync;
    final isInProgress = widget.syncManager.isSyncInProgress;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Sync status icon
            Icon(
              isInProgress 
                ? Icons.sync 
                : pendingCount > 0 
                  ? Icons.cloud_upload_outlined
                  : Icons.cloud_done,
              color: isInProgress 
                ? Colors.blue 
                : pendingCount > 0 
                  ? Colors.orange 
                  : Colors.green,
            ),
            const SizedBox(width: 8),
            
            // Status text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isInProgress 
                      ? 'Syncing...'
                      : pendingCount > 0 
                        ? '$pendingCount pending'
                        : 'Up to date',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (lastSync != null)
                    Text(
                      'Last sync: ${_formatTime(lastSync)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            
            // Manual sync button
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: isInProgress ? null : () => _triggerManualSync(),
              tooltip: 'Manual sync',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with current status
        _buildStatusHeader(),
        
        const SizedBox(height: 16),
        
        // Pending operations section
        if (widget.showPendingOperations) ...[
          _buildPendingOperationsSection(),
          const SizedBox(height: 16),
        ],
        
        // Sync history timeline
        if (widget.showSyncHistory) ...[
          _buildSyncHistorySection(),
        ],
      ],
    );
  }

  Widget _buildStatusHeader() {
    final pendingCount = widget.syncManager.pendingOperationsCount;
    final lastSync = widget.syncManager.lastSuccessfulSync;
    final isInProgress = widget.syncManager.isSyncInProgress;
    final isAutoSyncEnabled = widget.syncManager.isAutoSyncEnabled;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isInProgress 
                    ? Icons.sync 
                    : pendingCount > 0 
                      ? Icons.cloud_upload_outlined
                      : Icons.cloud_done,
                  color: isInProgress 
                    ? Colors.blue 
                    : pendingCount > 0 
                      ? Colors.orange 
                      : Colors.green,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync Status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        isInProgress 
                          ? 'Syncing in progress...'
                          : pendingCount > 0 
                            ? '$pendingCount operations pending'
                            : 'All data synchronized',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: isInProgress ? null : () => _triggerManualSync(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync Now'),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Additional status info
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                  'Auto-sync',
                  isAutoSyncEnabled ? 'Enabled' : 'Disabled',
                  isAutoSyncEnabled ? Colors.green : Colors.grey,
                ),
                if (lastSync != null)
                  _buildStatusChip(
                    'Last sync',
                    _formatTimestamp(lastSync),
                    Colors.blue,
                  ),
                _buildStatusChip(
                  'Pending',
                  '$pendingCount operations',
                  pendingCount > 0 ? Colors.orange : Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.withOpacity(0.2),
        child: Icon(
          Icons.info_outline,
          size: 16,
          color: color,
        ),
      ),
      label: Text('$label: $value'),
    );
  }

  Widget _buildPendingOperationsSection() {
    final pendingCount = widget.syncManager.pendingOperationsCount;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pending Operations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              pendingCount == 0 
                ? 'No operations pending sync'
                : '$pendingCount operations waiting to be synchronized',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (pendingCount > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncHistorySection() {
    final events = widget.syncManager.syncHistory.events
        .take(widget.maxEventsToShow)
        .toList();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Sync History',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showFullHistory(),
                  icon: const Icon(Icons.history),
                  label: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    'No sync events yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              )
            else
              Column(
                children: events.map((event) => _buildSyncEventTile(event)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncEventTile(SyncEvent event) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _getEventIcon(event),
        color: _getEventColor(event),
      ),
      title: Text(_getEventTitle(event)),
      subtitle: Text(_getEventSubtitle(event)),
      trailing: Text(_formatTime(event.timestamp)),
    );
  }

  IconData _getEventIcon(SyncEvent event) {
    if (event.success) {
      return Icons.check_circle;
    } else if (event.discardedCount > 0) {
      return Icons.delete_forever;
    } else {
      return Icons.error;
    }
  }

  Color _getEventColor(SyncEvent event) {
    if (event.success) {
      return Colors.green;
    } else if (event.discardedCount > 0) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  String _getEventTitle(SyncEvent event) {
    final typeText = event.type.name.toUpperCase();
    if (event.success) {
      return '$typeText SYNC - Success';
    } else if (event.discardedCount > 0) {
      return '$typeText SYNC - Partial (${event.discardedCount} discarded)';
    } else {
      return '$typeText SYNC - Failed';
    }
  }

  String _getEventSubtitle(SyncEvent event) {
    final parts = <String>[];
    
    if (event.syncedCount > 0) {
      parts.add('${event.syncedCount} synced');
    }
    if (event.failedCount > 0) {
      parts.add('${event.failedCount} failed');
    }
    if (event.discardedCount > 0) {
      parts.add('${event.discardedCount} discarded');
    }
    
    if (parts.isEmpty) {
      return 'No operations';
    }
    
    return parts.join(', ');
  }

  void _triggerManualSync() async {
    try {
      await widget.syncManager.syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  void _showFullHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SyncHistoryPage(
          syncManager: widget.syncManager,
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  String _formatTimestamp(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

/// A page that shows the full sync history
class SyncHistoryPage extends StatelessWidget {
  const SyncHistoryPage({
    Key? key,
    required this.syncManager,
  }) : super(key: key);

  final ServerSyncManager syncManager;

  @override
  Widget build(BuildContext context) {
    final events = syncManager.syncHistory.events;
    final history = syncManager.syncHistory;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showSyncStats(context),
          ),
        ],
      ),
      body: events.isEmpty
        ? const Center(
            child: Text('No sync events yet'),
          )
        : ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    _getEventIcon(event),
                    color: _getEventColor(event),
                  ),
                  title: Text(_getEventTitle(event)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_getEventSubtitle(event)),
                      if (event.error != null)
                        Text(
                          'Error: ${event.error}',
                          style: TextStyle(color: Colors.red[700]),
                        ),
                    ],
                  ),
                  trailing: Text(_formatFullTimestamp(event.timestamp)),
                ),
              );
            },
          ),
    );
  }

  void _showSyncStats(BuildContext context) {
    final history = syncManager.syncHistory;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatRow('Total Synced:', '${history.totalSynced}'),
            _buildStatRow('Total Failed:', '${history.totalFailed}'),
            _buildStatRow('Total Discarded:', '${history.totalDiscarded}'),
            const SizedBox(height: 16),
            if (history.lastSuccessfulSync != null)
              _buildStatRow(
                'Last Success:', 
                _formatFullTimestamp(history.lastSuccessfulSync!),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  IconData _getEventIcon(SyncEvent event) {
    if (event.success) {
      return Icons.check_circle;
    } else if (event.discardedCount > 0) {
      return Icons.delete_forever;
    } else {
      return Icons.error;
    }
  }

  Color _getEventColor(SyncEvent event) {
    if (event.success) {
      return Colors.green;
    } else if (event.discardedCount > 0) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  String _getEventTitle(SyncEvent event) {
    final typeText = event.type.name.toUpperCase();
    if (event.success) {
      return '$typeText SYNC - Success';
    } else if (event.discardedCount > 0) {
      return '$typeText SYNC - Partial (${event.discardedCount} discarded)';
    } else {
      return '$typeText SYNC - Failed';
    }
  }

  String _getEventSubtitle(SyncEvent event) {
    final parts = <String>[];
    
    if (event.syncedCount > 0) {
      parts.add('${event.syncedCount} synced');
    }
    if (event.failedCount > 0) {
      parts.add('${event.failedCount} failed');
    }
    if (event.discardedCount > 0) {
      parts.add('${event.discardedCount} discarded');
    }
    
    if (parts.isEmpty) {
      return 'No operations';
    }
    
    return parts.join(', ');
  }

  String _formatFullTimestamp(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}