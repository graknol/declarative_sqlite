# Default Value Logic Refactoring

## Overview
Extracted the default value handling logic from the `_insert` method into a separate, reusable `_applyDefaultValues` method. This improves code organization, testability, and maintainability.

## Changes Made

### New Method: `_applyDefaultValues`
```dart
/// Applies default values for columns that are missing from the provided values map
Map<String, Object?> _applyDefaultValues(String tableName, Map<String, Object?> values) {
  final tableDef = _getTableDefinition(tableName);
  final valuesWithDefaults = <String, Object?>{...values};
  
  // Generate default values for missing columns using callbacks and static defaults
  for (final col in tableDef.columns) {
    // Skip system columns - they're handled separately
    if (col.name.startsWith('system_')) continue;
    
    // If column value is not provided and has a default callback, call it
    if (!valuesWithDefaults.containsKey(col.name) && col.defaultValueCallback != null) {
      final defaultValue = col.defaultValueCallback!();
      if (defaultValue != null) {
        // Apply the same serialization logic as DbRecord.setValue
        final serializedValue = _serializeValueForColumn(defaultValue, col);
        valuesWithDefaults[col.name] = serializedValue;
      }
    }
    // If still no value and has a static default value, use it
    else if (!valuesWithDefaults.containsKey(col.name) && col.defaultValue != null) {
      // Apply the same serialization logic as DbRecord.setValue
      final serializedValue = _serializeValueForColumn(col.defaultValue, col);
      valuesWithDefaults[col.name] = serializedValue;
    }
  }
  
  return valuesWithDefaults;
}
```

### Simplified `_insert` Method
```dart
Future<String> _insert(String tableName, Map<String, Object?> values, Hlc hlc) async {
  final tableDef = _getTableDefinition(tableName);

  // Convert FilesetField values to database strings
  final convertedValues = _convertFilesetFieldsToValues(tableName, values);

  // Apply default values for missing columns
  final valuesToInsert = _applyDefaultValues(tableName, convertedValues);
  
  // Add system columns
  valuesToInsert['system_version'] = hlc.toString();
  // ... rest of method
}
```

## Benefits

### 🧹 **Code Organization**
- **Single Responsibility**: Default value logic is isolated and focused
- **Cleaner Methods**: `_insert` method is more readable and focused on its core responsibility
- **Logical Separation**: Default value handling is separate from database insertion logic

### 🔧 **Maintainability**
- **Easier Changes**: Default value logic can be modified without touching insertion logic
- **Bug Isolation**: Issues with default values are isolated to one method
- **Code Reuse**: Default value logic can potentially be reused elsewhere

### 🧪 **Testability**
- **Unit Testing**: `_applyDefaultValues` can be tested independently
- **Mock-Friendly**: Easier to test default value behavior in isolation
- **Focused Tests**: Can write specific tests for default value scenarios

### 📖 **Readability**
- **Clear Intent**: Method name clearly indicates its purpose
- **Reduced Complexity**: Each method has fewer responsibilities
- **Better Documentation**: Each method can have focused documentation

## Functional Behavior

### Default Value Processing
The extracted method handles two types of defaults:

1. **Dynamic Defaults (Callbacks)**:
   ```dart
   // Column definition with callback
   DbColumn(
     name: 'created_at',
     defaultValueCallback: () => DateTime.now(),
   )
   
   // Applied when column is missing from insert values
   ```

2. **Static Defaults**:
   ```dart
   // Column definition with static value
   DbColumn(
     name: 'status',
     defaultValue: 'active',
   )
   
   // Applied when column is missing and no callback is defined
   ```

### Serialization Integration
- Default values are automatically serialized using `_serializeValueForColumn`
- Ensures consistency with user-provided values
- Handles DateTime, FilesetField, and other complex types correctly

### System Column Handling
- System columns (prefixed with 'system_') are intentionally skipped
- System columns are handled separately in the insertion logic
- Prevents conflicts with automatically generated system values

## Usage Examples

### Before Refactoring
```dart
// Default value logic was embedded in _insert method
// Made the method long and hard to understand
// Mixed insertion logic with default value logic
```

### After Refactoring
```dart
// Clean separation of concerns
final convertedValues = _convertFilesetFieldsToValues(tableName, values);
final valuesToInsert = _applyDefaultValues(tableName, convertedValues);
// ... continue with insertion logic
```

## Future Enhancements

This refactoring enables future improvements:

### Potential Reuse
- Could be used in update operations if needed
- Could be used in bulk load operations
- Could be used in validation scenarios

### Enhanced Testing
- Can test default value edge cases independently
- Can test serialization of default values in isolation
- Can mock different column configurations easily

### Documentation
- Each method now has a clear, focused purpose
- Easier to document expected behavior
- Better API documentation for developers

## Backwards Compatibility

- ✅ **No Breaking Changes**: Public API remains unchanged
- ✅ **Same Behavior**: Functional behavior is identical
- ✅ **Performance**: No performance impact
- ✅ **Error Handling**: Same error handling behavior

This refactoring improves code quality without affecting any existing functionality or APIs.