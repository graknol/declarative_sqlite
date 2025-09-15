# Awareness Indicators

Microsoft Office-style awareness indicators that show who's currently viewing the same record or page. This feature provides real-time collaboration visibility with vibrant color-coded user avatars.

## Overview

The awareness system consists of:
- **AwarenessManager**: Handles periodic API calls and manages user presence
- **AwarenessIndicator**: Visual widgets displaying user avatars
- **AutoForm Integration**: Automatic awareness tracking in forms

![Awareness Indicators Demo](awareness_demo.png)

## Core Components

### AwarenessUser
Represents a user currently viewing a record/page:

```dart
const user = AwarenessUser(
  name: 'John Smith',
  userId: 'user123',      // Optional
  initials: 'JS',         // Optional - auto-generated if not provided
  color: 0xFF4285F4,      // Optional - auto-generated if not provided
);

// Auto-generated properties
print(user.displayInitials); // 'JS' (from name if not provided)
print(user.displayColor);    // Vibrant color based on name hash
```

### AwarenessContext
Defines what record/page users are viewing:

```dart
// Track users viewing a specific record
const context = AwarenessContext(
  tableName: 'documents',
  recordId: 123,
  route: '/documents/123',      // Optional - for route-based tracking
  additionalContext: {...},    // Optional - custom metadata
);
```

### AwarenessManager
Manages the periodic API calls and user presence tracking:

```dart
final manager = AwarenessManager(
  onFetchAwareness: (context) async {
    // Your API call to fetch who's viewing this context
    final response = await api.getViewers(
      table: context.tableName,
      recordId: context.recordId,
    );
    return response.userNames;
  },
  pollingInterval: Duration(seconds: 30),      // How often to poll
  offlineRetryInterval: Duration(minutes: 1),  // Retry interval when offline
  enableDebugLogging: true,                    // For development
);

// Start tracking awareness for a context
manager.startTracking(context);

// Get current users (immediate)
final users = manager.getAwarenessUsers(context);

// Get stream of updates (reactive)
manager.getAwarenessStream(context).listen((users) {
  print('${users.length} users viewing');
});

// Stop tracking when done
manager.stopTracking(context);
manager.dispose(); // Clean up
```

## Visual Indicators

### Basic Awareness Indicator
Standard Microsoft Office-style stacked circles:

```dart
AwarenessIndicator(
  users: currentUsers,
  size: 32.0,                // Avatar size
  maxVisible: 2,             // Show max 2 avatars + "+N" for extras
  spacing: 16.0,             // Overlap spacing between avatars
  showTooltip: true,         // Show hover tooltip with names
)
```

### Compact Indicator
Smaller version for dense layouts:

```dart
CompactAwarenessIndicator(
  users: currentUsers,
  size: 24.0,
  maxVisible: 3,
)
```

### Reactive Indicator
Automatically updates from AwarenessManager:

```dart
ReactiveAwarenessIndicator(
  awarenessManager: manager,
  context: AwarenessContext(
    tableName: 'documents',
    recordId: documentId,
  ),
  placeholder: Text('No viewers'), // Shown when no users
)
```

### Horizontal Layout
Shows users in a row instead of stacked:

```dart
HorizontalAwarenessIndicator(
  users: currentUsers,
  avatarSize: 28.0,
  spacing: 8.0,
  showNames: true,          // Show names next to avatars
)
```

### Badge Style
Just shows the count:

```dart
AwarenessBadge(
  users: currentUsers,
  backgroundColor: Colors.blue,
  textColor: Colors.white,
)
```

## AutoForm Integration

Enable awareness tracking in AutoForm widgets:

```dart
AutoForm(
  query: QueryBuilder().selectAll().from('documents'),
  primaryKey: documentId,
  title: 'Edit Document',
  
  // Enable awareness tracking
  enableAwarenessTracking: true,
  awarenessManager: awarenessManager,
  
  fields: [
    AutoFormField.text('title'),
    AutoFormField.text('content'),
  ],
)
```

This automatically:
- Starts tracking when form opens
- Shows awareness indicator in form header
- Stops tracking when form closes
- Includes route information if available

## Integration Examples

### App Bar
```dart
AppBar(
  title: Text('Document.docx'),
  actions: [
    ReactiveAwarenessIndicator(
      awarenessManager: manager,
      context: AwarenessContext(
        tableName: 'documents',
        recordId: documentId,
      ),
    ),
  ],
)
```

### List Tiles
```dart
ListTile(
  title: Text('Project Report.docx'),
  trailing: ReactiveAwarenessIndicator(
    awarenessManager: manager,
    context: AwarenessContext(
      tableName: 'documents',
      recordId: doc.id,
    ),
    size: 24.0,
  ),
)
```

### Cards
```dart
Card(
  child: Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Marketing Plan'),
          ReactiveAwarenessIndicator(
            awarenessManager: manager,
            context: AwarenessContext(
              tableName: 'projects',
              recordId: project.id,
            ),
          ),
        ],
      ),
      // ... card content
    ],
  ),
)
```

## Backend API Integration

### Simple REST API
```dart
AwarenessManager(
  onFetchAwareness: (context) async {
    final url = '/api/awareness/${context.tableName}/${context.recordId}';
    final response = await http.get(url);
    final data = json.decode(response.body);
    return List<String>.from(data['users']);
  },
)
```

### GraphQL
```dart
AwarenessManager(
  onFetchAwareness: (context) async {
    final result = await client.query(
      QueryOptions(
        document: gql('''
          query GetViewers(\$table: String!, \$recordId: ID!) {
            viewers(table: \$table, recordId: \$recordId) {
              name
            }
          }
        '''),
        variables: {
          'table': context.tableName,
          'recordId': context.recordId,
        },
      ),
    );
    
    return result.data?['viewers']
        ?.map<String>((viewer) => viewer['name'])
        ?.toList() ?? [];
  },
)
```

### WebSocket for Real-time Updates
```dart
class RealtimeAwarenessManager extends AwarenessManager {
  final WebSocketChannel channel;
  
  RealtimeAwarenessManager({required this.channel, ...}) : super(...) {
    // Listen for real-time updates
    channel.stream.listen((message) {
      final data = json.decode(message);
      if (data['type'] == 'awareness_update') {
        _handleAwarenessUpdate(data);
      }
    });
  }
  
  void _handleAwarenessUpdate(Map<String, dynamic> data) {
    final context = AwarenessContext(
      tableName: data['table'],
      recordId: data['recordId'],
    );
    final users = List<String>.from(data['users']);
    
    // Update immediately without waiting for next poll
    _updateAwarenessData(context, users);
  }
}
```

## Error Handling

The awareness system is designed to fail gracefully:

```dart
AwarenessManager(
  onFetchAwareness: (context) async {
    try {
      return await api.getViewers(context);
    } catch (e) {
      // Log error but don't throw - awareness is optional
      logger.warning('Failed to fetch awareness: $e');
      return []; // Return empty list on error
    }
  },
)
```

### Offline Detection

The manager automatically detects offline state and retries:

```dart
AwarenessManager(
  offlineRetryInterval: Duration(minutes: 1), // Retry every minute when offline
  onFetchAwareness: (context) async {
    // If this throws, manager goes into offline mode
    return await api.getViewers(context);
  },
)
```

## Performance Considerations

### Polling Strategy
- Default 30-second polling interval balances freshness with performance
- Manager automatically stops polling when no widgets are listening
- Supports multiple contexts with efficient batching

### Memory Management
- Automatic cleanup of inactive streams
- Disposes controllers when contexts are no longer tracked
- Weak references to prevent memory leaks

### Network Efficiency
- Only polls for active contexts
- Graceful offline handling with retry logic
- Debounced updates to prevent excessive API calls

## Customization

### Custom Colors
```dart
AwarenessIndicator(
  users: users.map((user) => AwarenessUser(
    name: user.name,
    color: getCustomColor(user.department), // Your color logic
  )).toList(),
)
```

### Custom Avatar Content
```dart
// Extend AwarenessIndicator for custom avatars
class CustomAwarenessIndicator extends AwarenessIndicator {
  @override
  Widget buildUserAvatar(AwarenessUser user) {
    return CircleAvatar(
      backgroundImage: NetworkImage(user.avatarUrl),
      child: user.avatarUrl == null ? Text(user.displayInitials) : null,
    );
  }
}
```

### Custom Tooltip Messages
```dart
AwarenessIndicator(
  users: users,
  tooltipBuilder: (users) {
    if (users.length == 1) {
      return '${users.first.name} is collaborating';
    }
    return '${users.length} people are collaborating';
  },
)
```

## Integration with Existing Sync Infrastructure

The awareness system complements the existing sync status indicators:

```dart
// Both sync status and awareness in form headers
AutoForm(
  enableSyncTracking: true,      // Shows sync status per field  
  enableAwarenessTracking: true, // Shows who's viewing the form
  syncManager: syncManager,
  awarenessManager: awarenessManager,
  // ... other properties
)
```

This provides complete collaborative visibility:
- **Sync indicators**: Show data flow status (local → saved → synced)
- **Awareness indicators**: Show who's currently viewing/editing
- **Combined**: Users see both data sync status and collaboration presence

## Example Implementation

See `example/awareness_demo.dart` for a complete working example with:
- Mock API simulation
- Multiple indicator styles
- Integration examples
- Interactive user count controls
- Realistic collaboration scenarios