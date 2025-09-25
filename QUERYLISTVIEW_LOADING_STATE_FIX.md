# QueryListView Loading State Fix

## Problem
The QueryListView widget was getting stuck in the loading state during initial render because:

1. **Asynchronous Initialization**: The streaming query creation was handled in `addPostFrameCallback`, which executes after the first build
2. **Missing setState**: When the streaming query was ready, no `setState` was called to trigger a rebuild
3. **Infinite Loading**: The widget would show the loading spinner indefinitely until some external event caused a rebuild

## Root Cause
```dart
// ❌ Problem: Called after first build, but no setState to trigger rebuild
WidgetsBinding.instance.addPostFrameCallback((_) {
  _initializeStreamingQuery(); // Creates query but doesn't rebuild
});
```

The widget lifecycle was:
1. `build()` called → `_streamingQuery` is null → shows loading state
2. `addPostFrameCallback` executes → `_streamingQuery` created → **NO REBUILD TRIGGERED**
3. Widget stuck in loading state forever

## Solution
Added `setState()` calls in all methods that create or modify the streaming query:

### 1. Initial Query Creation
```dart
void _initializeStreamingQuery() {
  final database = _getDatabase(context);
  if (database != null) {
    _currentDatabase = database;
    _createStreamingQuery(database);
    // ✅ Fix: Trigger rebuild now that streaming query is ready
    setState(() {});
  }
}
```

### 2. Database Changes
```dart
void _handleDatabaseChanges() {
  final newDatabase = _getDatabase(context);
  if (newDatabase != _currentDatabase) {
    _currentDatabase = newDatabase;
    if (newDatabase != null) {
      _createStreamingQuery(newDatabase);
      // ✅ Fix: Trigger rebuild now that streaming query is ready
      setState(() {});
    } else {
      _disposeStreamingQuery();
      // ✅ Fix: Trigger rebuild to show loading state
      setState(() {});
    }
  }
}
```

### 3. Query Recreation (Widget Updates)
```dart
// Only recreate the streaming query if there's a meaningful change
if (_lastQuerySignature != currentSignature || widget.mapper != oldWidget.mapper) {
  developer.log('QueryListView: Query changed, recreating stream', name: 'QueryListView');
  _createStreamingQuery(database);
  _lastQuerySignature = currentSignature;
  // ✅ Fix: Trigger rebuild now that streaming query has been recreated
  setState(() {});
}
```

## Widget Lifecycle (Fixed)
1. `build()` called → `_streamingQuery` is null → shows loading state
2. `addPostFrameCallback` executes → `_initializeStreamingQuery()` called
3. `_createStreamingQuery()` creates the query
4. `setState()` triggers rebuild
5. `build()` called again → `_streamingQuery` exists → `StreamBuilder` takes over
6. `StreamBuilder` handles all subsequent data updates

## Benefits
- **Immediate Response**: Loading state only shows for the minimal time needed
- **Smooth UX**: No stuck loading spinners
- **Proper Lifecycle**: Widget state correctly reflects streaming query availability
- **Consistent Behavior**: Works reliably across all initialization scenarios

## Testing
The fix handles all scenarios where the streaming query state changes:
- ✅ Initial widget mount with database available
- ✅ Initial widget mount with delayed database availability  
- ✅ Database changes via DatabaseProvider updates
- ✅ Query changes via widget property updates
- ✅ Database becomes unavailable (fallback to loading state)

## Impact
This is a critical UX fix that ensures QueryListView behaves as expected without getting stuck in loading states during normal initialization.