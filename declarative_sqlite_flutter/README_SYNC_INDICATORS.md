# Field Sync Status Indicators

This feature adds WhatsApp-style sync indicators to AutoForm fields, showing users the real-time status of their data changes as they flow from local edits through database saves to server synchronization.

## Visual Status Indicators

The sync indicators follow a familiar three-state pattern:

| Status | Icon | Color | Meaning |
|--------|------|-------|---------|
| **Local** | ○ (hollow circle) | Orange | Changes exist only in the widget (unsaved) |
| **Saved** | ✓○ (circle with tick) | Blue | Changes have been saved to local database |
| **Synced** | ✓● (filled circle with tick) | Green | Changes have been synchronized to server |

## Key Features

- **Real-time Updates**: Status indicators update automatically as data flows through the sync pipeline
- **User Attribution**: Shows who made changes when data is synced from the server
- **Non-intrusive Design**: Compact indicators that don't interfere with form layout
- **Optional Display**: Can be disabled per field or globally
- **Stream-based**: Uses reactive streams for efficient UI updates

## Basic Usage

### Enable Sync Tracking on AutoForm

```dart
AutoForm(
  query: QueryBuilder().selectAll().from('users'),
  primaryKey: userId,
  enableSyncTracking: true,  // Enable sync indicators
  syncManager: syncManager,  // Optional: for server sync status
  fields: [
    AutoFormField.text('name', 
      showSyncIndicator: true),  // Show indicator on this field
    AutoFormField.text('email', 
      showSyncIndicator: true),
  ],
  onSave: (data) async {
    // Save to database - fields will show "saved" status
    await dataAccess.update('users', data, where: 'id = ?', whereArgs: [userId]);
  },
)
```

### Standalone Sync Indicators

```dart
// Full-size indicator with tooltip
FieldSyncIndicator(
  syncInfo: FieldSyncInfo(
    status: FieldSyncStatus.synced,
    attribution: ChangeAttribution(
      userId: 'user123',
      userName: 'John Doe',
      timestamp: DateTime.now(),
    ),
  ),
)

// Compact indicator for dense layouts
CompactFieldSyncIndicator(
  syncInfo: FieldSyncInfo(status: FieldSyncStatus.saved),
)
```

### Manual Sync Status Management

```dart
// Create a sync tracker
final syncTracker = dataAccess.createSyncTracker(syncManager: syncManager);

// Track status changes
syncTracker.markFieldAsLocal('users', userId, 'name');
syncTracker.markFieldAsSaved('users', userId, 'name');
syncTracker.markFieldAsSynced('users', userId, 'name', 
  attribution: ChangeAttribution(
    userId: 'user456',
    userName: 'Jane Smith',
    timestamp: DateTime.now(),
  ),
);

// Listen to status changes
syncTracker.getFieldStatusStream('users', userId, 'name').listen((syncInfo) {
  print('Field status changed to: ${syncInfo.status}');
  if (syncInfo.attribution != null) {
    print('Changed by: ${syncInfo.attribution!.userName}');
  }
});
```

## Integration with Existing Sync Infrastructure

The sync indicators integrate seamlessly with the existing `ServerSyncManager` and LWW (Last Writer Wins) conflict resolution:

```dart
// Initialize with LWW support for sync tracking
final dataAccess = DataAccess(
  database: database,
  schema: schema,
  enableLWW: true,  // Required for sync tracking
);

// Create sync manager
final syncManager = ServerSyncManager(
  dataAccess: dataAccess,
  uploadCallback: uploadToServer,
);

// AutoForm will automatically:
// 1. Mark fields as "local" when user types
// 2. Mark fields as "saved" when onSave completes
// 3. Mark fields as "synced" when server sync completes
// 4. Show user attribution for server-originating changes
```

## Status Lifecycle

The typical lifecycle of a field's sync status:

1. **User starts typing** → Status becomes `local` (orange hollow circle)
2. **Form is saved** → Status becomes `saved` (blue circle with tick)  
3. **Server sync completes** → Status becomes `synced` (green filled circle with tick)
4. **Server changes received** → Status shows `synced` with user attribution

## Tooltips and User Attribution

Sync indicators show helpful tooltips:

- **Local**: "Changes not saved"
- **Saved**: "Saved to database 2m ago"
- **Synced**: "Synced to server by John Doe 5m ago"

## Customization Options

### Field-level Control

```dart
AutoFormField.text('notes',
  showSyncIndicator: false,  // Disable for this field
)

AutoFormField.text('sensitive_data',
  showSyncIndicator: true,   // Enable with custom behavior
)
```

### Form-level Control

```dart
AutoForm(
  enableSyncTracking: false,  // Disable all sync tracking
  // ... other properties
)
```

### Custom Indicator Styling

```dart
CompactFieldSyncIndicator(
  syncInfo: syncInfo,
  size: 12.0,  // Custom size
)

FieldSyncIndicator(
  syncInfo: syncInfo,
  size: 20.0,      // Larger indicator
  showTooltip: false,  // Disable tooltip
)
```

## Error Handling

The sync tracking system is designed to be resilient:

- If sync tracker initialization fails, forms continue to work without indicators
- Network failures don't affect the local/saved status tracking
- Corrupted sync state automatically resets to safe defaults

## Performance Considerations

- Uses efficient stream-based updates
- Minimal memory footprint per field
- Automatically cleans up streams when forms are disposed
- Debounced updates prevent excessive UI refreshes

## Migration from Existing Forms

Existing AutoForm implementations continue to work unchanged. To add sync indicators:

1. Add `enableSyncTracking: true` to AutoForm
2. Optionally add `syncManager` for server sync status
3. Individual fields show indicators by default (can be disabled per field)

The feature is designed to be completely backward compatible with zero breaking changes.