# Sync Status Widget

A Flutter widget that displays sync status information including a timeline of sync events and current pending operations count. This widget provides debugging capabilities for offline-first applications using the declarative_sqlite package.

## Features

- **Timeline View**: Chronological display of sync events with success/failure indicators
- **Compact Mode**: Minimal status indicator suitable for app bars or status sections
- **Full Debug Mode**: Comprehensive view with detailed sync information
- **Real-time Updates**: Automatic refresh of sync status information
- **Navigation**: Easy access to full sync history and statistics
- **Permanent Failure Handling**: Proper handling of 400-like errors by discarding operations

## Usage

### Basic Setup

```dart
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

// Create your sync manager
final syncManager = ServerSyncManager(
  dataAccess: dataAccess,
  uploadCallback: (operations) async {
    try {
      final response = await httpClient.post(url, body: operations);
      if (response.statusCode == 200) {
        return true; // Success
      } else if (response.statusCode == 400) {
        return false; // Permanent failure - discard operations
      } else {
        throw Exception('Server error ${response.statusCode}'); // Retry
      }
    } catch (e) {
      throw e; // Network errors - retry
    }
  },
);
```

### Compact Status Widget

Perfect for app bars, navigation drawers, or status sections:

```dart
SyncStatusWidget(
  syncManager: syncManager,
  compact: true,
)
```

### Full Debug Widget

Use in a dedicated debug/settings page:

```dart
SyncStatusWidget(
  syncManager: syncManager,
  refreshInterval: Duration(seconds: 5),
  maxEventsToShow: 20,
  showPendingOperations: true,
  showSyncHistory: true,
)
```

### Navigation to Full History

```dart
// From app bar action
IconButton(
  icon: Icon(Icons.debug_symbol),
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => SyncHistoryPage(syncManager: syncManager),
    ),
  ),
)
```

## Widget Properties

### SyncStatusWidget

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `syncManager` | `ServerSyncManager` | required | The sync manager to display status for |
| `refreshInterval` | `Duration` | `Duration(seconds: 5)` | How often to refresh the status display |
| `maxEventsToShow` | `int` | `20` | Maximum number of sync events to show in timeline |
| `showPendingOperations` | `bool` | `true` | Whether to show the pending operations section |
| `showSyncHistory` | `bool` | `true` | Whether to show the sync history timeline |
| `compact` | `bool` | `false` | Whether to use a compact layout |

## Sync Manager Enhancements

The `ServerSyncManager` has been enhanced with new properties:

### Properties

- `syncHistory`: Access to sync event timeline
- `lastSuccessfulSync`: Timestamp of last successful sync  
- `pendingOperationsCount`: Current pending operations count

### Sync History

```dart
final history = syncManager.syncHistory;

// Get all events (most recent first)
final events = history.events;

// Get recent events from last hour
final recentEvents = history.getRecentEvents(60);

// Get statistics
final totalSynced = history.totalSynced;
final totalFailed = history.totalFailed;
final totalDiscarded = history.totalDiscarded;
```

## Callback Contract

The upload callback now follows a specific contract for handling different failure types:

### Return Values

- `true`: Operation succeeded, mark as synced
- `false`: Permanent failure (400-like error), discard operations
- `Exception`: Temporary failure, retry with exponential backoff

### Example Implementation

```dart
Future<bool> uploadCallback(List<PendingOperation> operations) async {
  try {
    final response = await httpClient.post(
      'https://api.example.com/sync',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(operations.map((op) => op.toJson()).toList()),
    );
    
    switch (response.statusCode) {
      case 200:
      case 201:
        return true; // Success
        
      case 400:
      case 422:
        // Bad request - data is malformed, don't retry
        return false;
        
      case 401:
      case 403:
        // Auth errors - might be fixable, but don't retry immediately
        return false;
        
      case 500:
      case 502:
      case 503:
      case 504:
        // Server errors - retry
        throw Exception('Server error: ${response.statusCode}');
        
      default:
        // Unknown error - retry
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  } on SocketException {
    // Network error - retry
    throw Exception('Network connection failed');
  } on TimeoutException {
    // Timeout - retry
    throw Exception('Request timeout');
  } catch (e) {
    // Other errors - retry
    rethrow;
  }
}
```

## Event Types

### SyncEventType

- `SyncEventType.manual`: User-triggered sync
- `SyncEventType.automatic`: Timer-based sync  
- `SyncEventType.startup`: Initial sync when auto-sync starts

### SyncEvent Properties

Each sync event contains:

- `timestamp`: When the sync occurred
- `type`: Type of sync event
- `success`: Whether the sync was successful
- `operationCount`: Total operations processed
- `syncedCount`: Operations successfully synced
- `failedCount`: Operations that failed (will retry)
- `discardedCount`: Operations discarded (permanent failures)
- `error`: Error message if sync failed

## Example Integration

Here's a complete example of integrating the sync status widget into an app:

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ServerSyncManager syncManager;
  
  @override
  void initState() {
    super.initState();
    _initSyncManager();
  }
  
  void _initSyncManager() {
    syncManager = ServerSyncManager(
      dataAccess: dataAccess,
      uploadCallback: _uploadToServer,
    );
    syncManager.startAutoSync();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My App'),
        actions: [
          // Compact sync status in app bar
          SyncStatusWidget(
            syncManager: syncManager,
            compact: true,
          ),
          IconButton(
            icon: Icon(Icons.debug_symbol),
            onPressed: _showSyncDebugPage,
          ),
        ],
      ),
      // ... rest of app
    );
  }
  
  void _showSyncDebugPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text('Sync Debug')),
          body: SyncStatusWidget(
            syncManager: syncManager,
            compact: false,
          ),
        ),
      ),
    );
  }
}
```

## Best Practices

1. **Error Handling**: Implement proper error categorization in your upload callback
2. **User Feedback**: Use the compact widget to show users sync status
3. **Debug Access**: Provide easy access to the debug page for troubleshooting
4. **Performance**: Use appropriate refresh intervals based on your needs
5. **Permanent Failures**: Return `false` for 400-like errors to avoid infinite retries