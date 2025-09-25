# Value Serialization Fix for Insert/Update Methods

## Problem
The `insert()` and `update()` methods in `DeclarativeDatabase` were not properly serializing input values according to column type definitions. This caused issues when inserting/updating values like:
- `DateTime` objects (should be serialized to ISO8601 strings)
- `FilesetField` objects (should be converted to database strings)
- Other custom types that require serialization

## Root Cause
The methods were passing user-provided values directly to the internal `_insert()` and `_update()` methods without applying the same serialization logic used by `DbRecord.setValue()`.

### Before (Problematic)
```dart
// User provides DateTime object
await db.insert('events', {
  'name': 'Meeting',
  'start_date': DateTime.now(), // ❌ Raw DateTime passed to database
});

// This would cause SQL errors or incorrect storage
```

### After (Fixed)
```dart
// User provides DateTime object  
await db.insert('events', {
  'name': 'Meeting',
  'start_date': DateTime.now(), // ✅ Automatically serialized to ISO8601 string
});

// Values are properly serialized before database storage
```

## Implementation

### New Helper Method
Added `_serializeValuesForTable()` method that:
1. Gets the table definition from the schema
2. Looks up each column's type definition  
3. Applies the same serialization logic as `DbRecord.setValue()`
4. Handles unknown columns gracefully (passes through as-is)

```dart
Map<String, Object?> _serializeValuesForTable(String tableName, Map<String, Object?> values) {
  final tableDef = _getTableDefinition(tableName);
  final serializedValues = <String, Object?>{};
  
  for (final entry in values.entries) {
    final columnName = entry.key;
    final value = entry.value;
    
    // Find the column definition
    final column = tableDef.columns.where((col) => col.name == columnName).firstOrNull;
    
    if (column != null) {
      // Serialize using column definition
      serializedValues[columnName] = _serializeValueForColumn(value, column);
    } else {
      // Column not found in schema - pass through as-is (might be system column)
      serializedValues[columnName] = value;
    }
  }
  
  return serializedValues;
}
```

### Updated Methods
Both `insert()` and `update()` now serialize input values:

```dart
Future<String> insert(String tableName, Map<String, Object?> values) async {
  return await DbExceptionWrapper.wrapCreate(() async {
    // ✅ Serialize input values using column definitions
    final serializedValues = _serializeValuesForTable(tableName, values);
    
    final systemId = await _insert(tableName, serializedValues, now);
    // ... rest of method
  }, tableName: tableName);
}
```

## Serialization Rules

The fix applies consistent serialization rules across all value types:

### DateTime Serialization
```dart
// Input: DateTime object
DateTime.now()
// Output: ISO8601 string
"2025-09-25T14:30:00.000Z"
```

### FilesetField Serialization  
```dart
// Input: FilesetField object
FilesetField([file1, file2])
// Output: Database JSON string
'["file1_id", "file2_id"]'
```

### Other Types
- `text`, `guid`, `integer`, `real`: Pass through unchanged
- `null` values: Pass through unchanged
- Unknown column types: Pass through unchanged for backwards compatibility

## Benefits

### 🔧 **Consistency**
- Same serialization logic across `DbRecord.setValue()`, `insert()`, and `update()`
- No more discrepancies between different data modification methods

### 🛡️ **Type Safety** 
- Prevents SQL errors from incorrect value types
- Ensures database storage format consistency

### 🎯 **Developer Experience**
- Can use native Dart types directly in insert/update calls
- No need to manually serialize DateTime objects
- FilesetField objects work seamlessly

### ⚡ **Backwards Compatible**
- Existing code continues to work unchanged
- Unknown columns pass through safely
- No performance impact for simple types

## Usage Examples

### DateTime Handling
```dart
// Before fix - would cause errors
await db.insert('events', {
  'title': 'Meeting',
  'start_time': DateTime(2025, 9, 25, 14, 30), // ❌ SQL error
});

// After fix - works seamlessly  
await db.insert('events', {
  'title': 'Meeting', 
  'start_time': DateTime(2025, 9, 25, 14, 30), // ✅ Auto-serialized
});
```

### FilesetField Handling
```dart
// Before fix - would cause errors
final fileset = FilesetField.fromFiles([myFile]);
await db.insert('documents', {
  'name': 'Report',
  'attachments': fileset, // ❌ Complex object error
});

// After fix - works seamlessly
final fileset = FilesetField.fromFiles([myFile]);
await db.insert('documents', {
  'name': 'Report',
  'attachments': fileset, // ✅ Auto-serialized to JSON
});
```

### Update Operations
```dart
// Both insert and update now handle serialization consistently
await db.update('events', {
  'end_time': DateTime.now(), // ✅ Properly serialized
}, where: 'id = ?', whereArgs: [eventId]);
```

## Technical Details

### Schema Integration
- Leverages existing `_getTableDefinition()` to get column metadata
- Uses existing `_serializeValueForColumn()` logic for consistency
- Gracefully handles columns not defined in schema

### Error Handling
- Unknown columns pass through unchanged (backwards compatibility)
- Null values handled properly across all column types
- No additional exceptions introduced

### Performance
- Minimal overhead: only processes columns that have values
- Schema lookups are fast (in-memory)
- Serialization logic is lightweight

This fix ensures that all database modification methods (`insert`, `update`, and `DbRecord.setValue`) use consistent value serialization, preventing type-related errors and ensuring proper data storage.