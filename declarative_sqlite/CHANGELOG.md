## 1.4.0

### 🚀 Major Features
- **Reactive Synchronization**: Added stream-based dirty row notifications for efficient, real-time sync
  - New `onDirtyRowAdded` stream on `DeclarativeDatabase` for immediate change notifications
  - Eliminates need for polling - get instant notifications when data changes
  - Zero overhead when no changes occur, perfect for offline-first applications
  - Broadcast stream support for multiple listeners
  - Enhanced `DirtyRowStore` interface with `Stream<DirtyRow> get onRowAdded`
  - Automatic cleanup and disposal of stream resources
- **Enhanced Exception Handling**: Exported comprehensive database exception classes for advanced error handling
  - `DbOperationType` and `DbErrorCategory` enums for categorizing errors
  - Specific exception types: `DbCreateException`, `DbReadException`, `DbUpdateException`, `DbDeleteException`
  - `DbTransactionException`, `DbConnectionException`, `DbMigrationException` for system-level errors
  - `DbExceptionMapper` utility for platform-specific exception mapping

### 🎯 Developer Experience
- **Real-time Sync**: Replace inefficient polling with reactive streams
  ```dart
  // Old way: Poll every 30 seconds
  Timer.periodic(Duration(seconds: 30), (_) => checkForChanges());
  
  // New way: Immediate reactive response
  database.onDirtyRowAdded?.listen((dirtyRow) => triggerSync());
  ```
- **Production-Ready Patterns**: Built-in support for debouncing, error isolation, and resource cleanup
- **Type-Safe Error Handling**: Catch specific database exception types for better error recovery
- **Better Battery Life**: No periodic checks when no data changes occur

### 🛠️ Technical Improvements
- Enhanced `SqliteDirtyRowStore` with `StreamController<DirtyRow>.broadcast()`
- Proper stream disposal in `DeclarativeDatabase.close()`
- Comprehensive test coverage for reactive streams with 9 test scenarios
- Backward compatibility maintained - all existing APIs unchanged

### 📚 Documentation
- Updated data synchronization guide with reactive patterns and best practices
- Added comparison between polling vs reactive approaches
- Production examples with debouncing and error handling
- Enhanced README with reactive synchronization feature

### ✅ Quality Assurance
- All existing tests continue to pass
- New comprehensive test suite for reactive functionality
- Static analysis verification
- Export verification for all new functionality

## 1.3.0

### Features
- **Constraint Violation Handling in bulkLoad**: Added graceful constraint violation handling with `ConstraintViolationStrategy`
  - `throwException` (default): Maintains existing behavior - throws on constraint violations
  - `skip`: Silently skips problematic rows and continues processing valid ones
  - Comprehensive constraint detection for unique, primary key, check, foreign key, and NOT NULL violations
  - Detailed logging for monitoring and debugging constraint violation events
- **Fixed Unique Constraint Generation**: Resolved issue where unique keys weren't properly creating `CREATE UNIQUE INDEX` statements
  - Unique constraints now generate proper SQL: `CREATE UNIQUE INDEX uniq_table_column ON table (column)`
  - Improved migration script generation to handle both regular indexes and unique constraints

### Developer Experience
- Enhanced bulkLoad method for server synchronization scenarios
- Better error handling and logging for constraint violations
- Safer bulk loading operations with granular control over error handling

### Bug Fixes
- Fixed missing unique constraint generation in schema migration scripts
- Improved constraint violation detection and categorization

### Documentation
- Updated bulkLoad method documentation with constraint violation handling examples
- Enhanced migration guide with unique constraint best practices

## 1.2.0

### Features
- **Unified Save Method**: Enhanced `DbRecord.save()` to automatically handle both insert and update operations
  - `save()` now intelligently detects whether a record is new (needs INSERT) or existing (needs UPDATE)
  - Eliminates the need to manually choose between `insert()` and `save()` for updates
  - Added `isNewRecord` property to check whether a record needs insertion
  - Deprecated explicit `insert()` method in favor of unified `save()` approach
  - After successful insert via `save()`, record data is automatically refreshed with all system columns
  - Multiple consecutive `save()` calls work seamlessly on the same record

### Developer Experience
- Simplified CRUD workflow - just use `save()` for everything
- Reduced cognitive load - no need to track insert vs update state manually
- Better API consistency across create and update operations

### Documentation
- Updated data modeling guide with unified save examples
- Enhanced CRUD operations documentation with recommended patterns
- Added comprehensive example demonstrating unified save approach

## 1.1.0

### Features
- **Non-LWW Column Protection**: Added protection against updating non-LWW columns on server-origin rows
  - Prevents data corruption in distributed systems by restricting updates to LWW columns only on rows that originated from server
  - Local-origin rows can still update all columns freely
  - Throws `StateError` when attempting to update non-LWW columns on server-origin rows
  - Enhanced `DbRecord.setValue()` with origin validation
- **Improved Dirty Row Tracking**: Enhanced dirty row tracking to differentiate between full row updates (local origin) and partial updates (server origin)

### Data Safety
- Added `isLocalOrigin` property to `DbRecord` for checking row origin
- Enhanced synchronization safety with column-level update restrictions
- Maintained backward compatibility for existing local data operations

## 1.0.2

### Breaking Changes
- Removed foreign key functionality from KeyBuilder and DbKey classes
- Foreign key constraint handling removed from exception system
- Architecture now favors application-level relationship management

### Documentation
- Updated all documentation to remove foreign key references
- Improved examples focusing on application-domain relationships

## 1.0.1

### Features
- Complete rewrite with simplified, reactive database operations
- Declarative schema definition with automatic table creation
- Query builder with type-safe operations
- Streaming queries for reactive UIs
- File repository integration
- Comprehensive test coverage

### API Changes
- Removed transaction support for simplicity
- Removed sync manager and HLC support
- Streamlined `DeclarativeDatabase.open()` method
- Updated query methods: `query()`, `queryMaps()`, `streamRecords()`
- Simplified schema building with `SchemaBuilder`

### Documentation
- Updated all examples to use current API
- Added comprehensive test suite
- Updated README with correct usage patterns