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