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