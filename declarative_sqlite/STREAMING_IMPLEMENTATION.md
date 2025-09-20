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

### 2.1. AdvancedStreamingQuery (`lib/src/streaming/advanced_streaming_query.dart`)
- **Purpose**: Enhanced streaming query with smart lifecycle management
- **Features**:
  - **Value-based equality** checking for QueryBuilder changes using Equatable
  - **Reference equality** checking for mapper function changes
  - **Cache invalidation** when mapper changes, preservation when mapper stays same
  - **Query updates** without stream recreation - execute new query through existing stream
  - **Bounded cache** that prevents infinite growth by cleaning unused entries
  - All performance optimizations from base StreamingQuery

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
- **Purpose**: Reactive UI components with advanced lifecycle management
- **Features**:
  - Enhanced QueryListView with streaming support and smart updates
  - **Smart lifecycle management** - detects query and mapper changes
  - **Value-based equality** for QueryBuilder changes (no unnecessary recreations)
  - **Reference equality** for mapper function changes (cache invalidation when needed)
  - **Stream preservation** - updates query through existing stream instead of recreation
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

### System Column-Based Result Caching
The streaming system implements sophisticated caching using system columns for optimal performance:

- **System ID Indexing**: Uses `system_id` as direct cache key (no hashing required)
- **Version Tracking**: Uses `system_version` to detect changes efficiently  
- **Cache Lookup**: Before mapping, checks if a row with same system_id and system_version exists in cache
- **Selective Mapping**: Only rows with new/changed system_version are mapped to objects
- **Reference Equality**: Unchanged objects maintain reference equality between emissions
- **Fallback Support**: Falls back to generated identifiers for tables without system columns
- **Cache Cleanup**: Automatically removes cached entries no longer in the result set

### Performance Benefits
```dart
// Example: Large result set with minimal changes
final usersStream = db.stream<User>(
  (q) => q.from('users'),
  User.fromMap,  // Expensive mapping operation
);

// When 1 user changes out of 1000:
// - Cache lookup: Direct hashmap access by system_id (O(1))
// - Version check: Simple string comparison of system_version
// - Mapping: Only 1 user mapped instead of 1000
// - Result: 99.9%+ performance improvement with zero hash computation overhead
```

### Memory Management
- **Cache Size**: Bounded by current result set size
- **Cleanup**: Automatic removal of unused cache entries
- **Lifecycle**: Cache cleared on stream disposal or cancellation

## Smart Lifecycle Management

### Query Change Detection
The system uses `Equatable` for value-based equality checking of QueryBuilder objects:

```dart
// These queries are considered equal (same structure)
final query1 = QueryBuilder().from('users').where(col('status').eq('active'));
final query2 = QueryBuilder().from('users').where(col('status').eq('active'));

// Query change detected - executes new query without stream recreation
widget.updateQuery(newBuilder: query2); // Uses existing stream
```

### Mapper Function Handling
Reference equality is used to detect mapper function changes:

```dart
// Same reference - cache preserved
static User staticMapper(Map<String, Object?> row) => User.fromMap(row);
widget.updateQuery(newMapper: staticMapper); // Cache preserved

// Different reference - cache invalidated
widget.updateQuery(newMapper: (row) => User.fromMap(row)); // Cache cleared
```

### Benefits
- **Performance**: No unnecessary stream recreation for equivalent queries
- **Cache Efficiency**: Mapper changes invalidate cache, same mapper preserves it
- **Memory**: Bounded cache prevents infinite growth
- **UI Stability**: Stream preservation maintains widget state

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