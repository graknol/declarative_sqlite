# Method Reordering Documentation

## Overview

The methods in `DeclarativeDatabase` have been reordered to follow a logical dependency structure where methods that use other methods appear before the methods they depend on, following the requested pattern: init → build → dispose, and insert → update → delete operations.

## New Method Organization

### 1. Class Structure & Initialization
- `DeclarativeDatabase._internal` (constructor)
- `DeclarativeDatabase._inTransaction` (constructor) 
- `open` (static factory method)
- `close` (cleanup method)

### 2. Cache and Registry Methods
- `registerRecord`
- `getRecordFromCache`

### 3. Raw SQL Methods (lowest level)
- `execute`
- `rawQuery`
- `rawUpdate` 
- `rawInsert`
- `rawDelete`

### 4. Helper and Utility Methods
These are used by higher-level methods and appear before their consumers:

- `_getTableDefinition` - Schema lookup utility
- `_serializeValueForColumn` - Value serialization 
- `_serializeValuesForTable` - Batch value serialization
- `_applyDefaultValues` - Default value application
- `_convertFilesetFieldsToValues` - Fileset conversion for storage
- `_transformFilesetColumns` - Fileset conversion for retrieval
- `_createFilesetField` - FilesetField creation helper
- `_validateForUpdateQuery` - Query validation
- `_isSimpleTableQuery` - Query type detection

### 5. Query Methods (Read Operations)
These use the helper methods defined above:

- `queryMaps`, `queryMapsWith`
- `query`, `queryWith` 
- `queryTable`, `queryFirst`
- `queryTyped`, `queryTypedWith`, `queryTableTyped`

### 6. Streaming Query Methods
These build on the query methods:

- `stream`, `streamMapsWith`
- `streamRecords`, `streamRecordsWith`
- `streamTyped`, `streamTypedWith`

### 7. Transaction Management
- `transaction`

### 8. Insert Methods (CREATE operations)
Following the init → build → dispose pattern, insert comes first in CRUD:

- `insert` (public API)
- `_insert` (private implementation)

### 9. Update Methods (UPDATE operations)
- `update` (public API)
- `_update` (private implementation)

### 10. Delete Methods (DELETE operations)
- `delete` (public API)

### 11. Bulk Operations
Uses insert and update operations:

- `bulkLoad`

### 12. Static Helper Functions
Utility functions at the bottom:

- `_setSettingIfNotSet`
- `_setSetting` 
- `_getSetting`

## Benefits of This Organization

1. **Dependency Flow**: Helper methods appear before methods that use them
2. **Logical Grouping**: Related functionality is grouped together
3. **CRUD Order**: Operations follow init → build → dispose pattern (insert → update → delete)
4. **Readability**: Easier to understand method dependencies and relationships
5. **Maintainability**: Changes to helper methods are easier to trace to consumers

## Verification

✅ **Core Package**: `dart analyze` - No issues found
✅ **Demo Package**: `flutter analyze` - Only unrelated linting warnings
✅ **Functionality**: All existing functionality preserved, no breaking changes

This reordering maintains complete backwards compatibility while improving code organization and developer experience.