import 'package:flutter/material.dart';

/// Represents the synchronization status of a form field value
enum FieldSyncStatus {
  /// Value exists only locally in the widget (unsaved)
  local,
  
  /// Value has been saved to the local database
  saved,
  
  /// Value has been synchronized to the server
  synced,
}

/// Information about who made a change and when
class ChangeAttribution {
  const ChangeAttribution({
    required this.userId,
    required this.userName,
    required this.timestamp,
  });
  
  final String userId;
  final String userName;
  final DateTime timestamp;
}

/// Data class that tracks sync status and attribution for a field value
class FieldSyncInfo {
  const FieldSyncInfo({
    required this.status,
    this.attribution,
    this.lastSyncTime,
  });
  
  final FieldSyncStatus status;
  final ChangeAttribution? attribution;
  final DateTime? lastSyncTime;
  
  /// Creates a copy with updated status
  FieldSyncInfo copyWith({
    FieldSyncStatus? status,
    ChangeAttribution? attribution,
    DateTime? lastSyncTime,
  }) {
    return FieldSyncInfo(
      status: status ?? this.status,
      attribution: attribution ?? this.attribution,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

/// A small visual indicator widget that shows the sync status of a form field
/// Following WhatsApp's pattern: hollow circle -> circle with tick -> filled circle with tick
class FieldSyncIndicator extends StatelessWidget {
  const FieldSyncIndicator({
    Key? key,
    required this.syncInfo,
    this.size = 16.0,
    this.showTooltip = true,
  }) : super(key: key);
  
  final FieldSyncInfo syncInfo;
  final double size;
  final bool showTooltip;
  
  @override
  Widget build(BuildContext context) {
    final widget = _buildIndicator(context);
    
    if (!showTooltip) {
      return widget;
    }
    
    return Tooltip(
      message: _getTooltipMessage(),
      child: widget,
    );
  }
  
  Widget _buildIndicator(BuildContext context) {
    switch (syncInfo.status) {
      case FieldSyncStatus.local:
        return _buildLocalIndicator();
      case FieldSyncStatus.saved:
        return _buildSavedIndicator();
      case FieldSyncStatus.synced:
        return _buildSyncedIndicator();
    }
  }
  
  /// Hollow circle for local-only changes
  Widget _buildLocalIndicator() {
    return Icon(
      Icons.radio_button_unchecked,
      size: size,
      color: Colors.orange,
    );
  }
  
  /// Circle with checkmark for database-saved changes
  Widget _buildSavedIndicator() {
    return Icon(
      Icons.check_circle_outline,
      size: size,
      color: Colors.blue,
    );
  }
  
  /// Filled circle with checkmark for server-synced changes
  Widget _buildSyncedIndicator() {
    return Icon(
      Icons.check_circle,
      size: size,
      color: Colors.green,
    );
  }
  
  String _getTooltipMessage() {
    switch (syncInfo.status) {
      case FieldSyncStatus.local:
        return 'Changes not saved';
      case FieldSyncStatus.saved:
        final time = syncInfo.lastSyncTime;
        final timeStr = time != null ? _formatTime(time) : '';
        return 'Saved to database${timeStr.isNotEmpty ? ' $timeStr' : ''}';
      case FieldSyncStatus.synced:
        final time = syncInfo.lastSyncTime;
        final attribution = syncInfo.attribution;
        final timeStr = time != null ? _formatTime(time) : '';
        final userStr = attribution != null ? 'by ${attribution.userName}' : '';
        return 'Synced to server${userStr.isNotEmpty ? ' $userStr' : ''}${timeStr.isNotEmpty ? ' $timeStr' : ''}';
    }
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

/// Compact version of the sync indicator for use in dense layouts
class CompactFieldSyncIndicator extends StatelessWidget {
  const CompactFieldSyncIndicator({
    Key? key,
    required this.syncInfo,
    this.size = 12.0,
  }) : super(key: key);
  
  final FieldSyncInfo syncInfo;
  final double size;
  
  @override
  Widget build(BuildContext context) {
    Color color;
    switch (syncInfo.status) {
      case FieldSyncStatus.local:
        color = Colors.orange;
        break;
      case FieldSyncStatus.saved:
        color = Colors.blue;
        break;
      case FieldSyncStatus.synced:
        color = Colors.green;
        break;
    }
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: syncInfo.status == FieldSyncStatus.synced ? color : Colors.transparent,
        border: Border.all(
          color: color,
          width: 1.5,
        ),
      ),
      child: syncInfo.status != FieldSyncStatus.local
          ? Icon(
              Icons.check,
              size: size * 0.7,
              color: syncInfo.status == FieldSyncStatus.synced ? Colors.white : color,
            )
          : null,
    );
  }
}