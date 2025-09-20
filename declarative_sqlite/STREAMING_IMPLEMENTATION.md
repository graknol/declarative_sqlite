# Streaming Query Results Implementation Summary

## Overview
This implementation adds comprehensive streaming query support to declarative_sqlite, enabling automatic query re-execution and result emission whenever underlying data changes.

## Key Components

### 1. QueryDependencyAnalyzer (`lib/src/streaming/query_dependency_analyzer.dart`)
- **Purpose**: Analyzes queries to extract dependencies using schema metadata
- **Features**:
  - **Schema-aware analysis**: Uses table and view definitions for accurate dependency detection
  - **Recursive view analysis**: Automatically detects dependencies of views on underlying tables
  - **Column validation**: Validates that referenced columns exist in the schema
  - **System column support**: Recognizes system columns (system_id, system_version, etc.)
  - **Fallback parsing**: Maintains regex-based parsing for backward compatibility

### 2. StreamingQuery (`lib/src/streaming/streaming_query.dart`)
- **Purpose**: Manages individual streaming query lifecycle with performance optimization
- **Features**:
  - Broadcast stream controller for multiple listeners
  - Automatic query execution on first subscription
  - **Hash-based result caching** for performance optimization
  - **Reference equality preservation** for unchanged objects
  - **Selective mapping** - only maps rows that have changed
  - Generic type support with custom mappers
  - Proper memory management and disposal

### 3. QueryStreamManager (`lib/src/streaming/query_stream_manager.dart`)
- **Purpose**: Coordinates multiple streaming queries
- **Features**:
  - Registry of active streaming queries
  - Concurrent refresh of affected queries
  - Table and column-level change notifications
  - Automatic cleanup of inactive queries
  - Performance optimization through batch operations

### 4. Database Integration (`lib/src/database.dart`)
- **Purpose**: Integrates streaming into core database operations
- **Features**:
  - New `stream()` and `streamWith()` methods
  - Change detection hooks in insert/update/delete/bulkLoad
  - Automatic stream manager lifecycle management
  - Backward compatibility with existing query methods

### 5. Flutter Widget Integration (`declarative_sqlite_flutter/lib/src/query_list_view.dart`)
- **Purpose**: Reactive UI components
- **Features**:
  - Enhanced QueryListView with streaming support
  - Backward compatibility with mock data fallback
  - StreamBuilder integration for automatic UI updates
  - Generic type support with custom mappers

## API Usage

### Basic Streaming Query
```dart
final usersStream = db.stream<User>(
  (q) => q.from('users').where(col('status').eq('active')),
  User.fromMap,
);

usersStream.listen((users) {
  print('Active users: ${users.length}');
});
```

### Flutter Widget
```dart
QueryListView<User>(
  database: db,
  query: (q) => q.from('users'),
  mapper: User.fromMap,
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
  itemBuilder: (context, user) => UserTile(user),
)
```

## Performance Optimizations

### Hash-Based Result Caching
The streaming system implements sophisticated caching to minimize expensive mapping operations:

- **Row Hashing**: Each database row (Map) gets a computed hash code based on its contents
- **Cache Lookup**: Before mapping, the system checks if a row with the same hash exists in cache
- **Selective Mapping**: Only rows with new/changed hash codes are mapped to objects
- **Reference Equality**: Unchanged objects maintain reference equality between emissions
- **Cache Cleanup**: Automatically removes cached entries no longer in the result set

### Performance Benefits
```dart
// Example: Large result set with minimal changes
final usersStream = db.stream<User>(
  (q) => q.from('users'),
  User.fromMap,  // Expensive mapping operation
);

// When 1 user changes out of 1000:
// - Old approach: Maps all 1000 users
// - New approach: Maps only 1 user (99.9% savings)
// - Reference equality: 999 users are identical objects
```

### Memory Management
- **Cache Size**: Bounded by current result set size
- **Cleanup**: Automatic removal of unused cache entries
- **Lifecycle**: Cache cleared on stream disposal or cancellation

## Performance Characteristics

### Dependency Analysis
- **Approach**: Schema metadata-driven with SQL validation
- **Complexity**: O(n) where n is the number of query components
- **Memory**: Minimal, leverages existing schema objects
- **Accuracy**: High for all query types, with recursive view support

### Change Detection
- **Triggering**: Only affected queries are refreshed
- **Concurrency**: Multiple queries refresh in parallel
- **Overhead**: Minimal schema lookups and validation
- **Performance**: Hash-based caching minimizes mapping operations

### Stream Management
- **Memory**: Automatic cleanup of inactive streams and result cache
- **Scalability**: Efficient with hundreds of concurrent streams
- **Lifecycle**: Automatic registration/deregistration
- **Caching**: Hash-based result caching with reference equality preservation

## Testing

### Test Coverage
- **Schema-aware Tests**: Dependency analysis with schema validation
- **Integration Tests**: Full streaming workflow with database operations
- **View Dependencies**: Recursive view dependency detection
- **Column Validation**: Schema-based column existence checks
- **Error Handling**: Graceful handling of invalid queries

### Validation Results
- ✅ Schema-aware dependency analysis working correctly
- ✅ Recursive view dependency detection functioning
- ✅ Column validation against schema verified
- ✅ Memory management and cleanup validated
- ✅ Flutter widget integration prepared

## Key Improvements Over Regex-Only Approach

### Enhanced Accuracy
1. **View Dependencies**: Automatically detects when queries depend on views and recursively analyzes the underlying tables
2. **Column Validation**: Only includes columns that actually exist in the schema
3. **Table Validation**: Validates table and view names against the schema
4. **System Columns**: Properly recognizes system columns like system_id, system_version

### Better Architecture
1. **Schema Integration**: Leverages existing schema metadata instead of parsing SQL strings
2. **Recursive Analysis**: Traverses view definitions to find all transitive dependencies
3. **Type Safety**: Uses strongly-typed schema objects
4. **Maintainability**: Easier to extend and modify than regex patterns

### Example Improvements
```dart
// Query that depends on a view
final stream = db.stream((q) => q.from('active_users'), User.fromMap);

// Old approach: Only detects 'active_users' 
// New approach: Detects 'active_users' AND underlying 'users' table

// When users table changes, stream correctly updates even though
// the query references the view, not the table directly
await db.insert('users', {...}); // ✅ Stream updates correctly
```

## Future Enhancements

### Short-term Improvements
1. **QueryBuilder Integration**: Direct access to QueryBuilder internal state
2. **Complex View Analysis**: Better handling of views with subqueries
3. **Performance Optimization**: Caching of analyzed dependencies
4. **Enhanced Validation**: More sophisticated column and type checking

### Long-term Possibilities
1. **Query Optimization**: Intelligent query planning based on dependencies
2. **Partial Updates**: Emit only changed rows instead of full result sets
3. **Dependency Graphs**: Visual representation of query dependencies
4. **Smart Caching**: Cache query results with dependency-based invalidation

## Migration Impact

### Backward Compatibility
- ✅ All existing APIs unchanged
- ✅ Fallback to regex-based parsing when schema unavailable
- ✅ No breaking changes to public interfaces
- ✅ Existing tests continue to pass

### New Dependencies
- Schema objects now required for optimal dependency analysis
- Recursive view analysis adds minimal computational overhead
- Enhanced accuracy may change dependency sets for complex queries

This implementation represents a significant architectural improvement, moving from string-based parsing to metadata-driven analysis while maintaining full backward compatibility and delivering superior accuracy for complex queries involving views and sophisticated table relationships.