## 1.0.1

### Breaking Changes

- **Platform Dependencies**: Moved `sqflite_common` to dev_dependencies. Users must now explicitly add platform-specific SQLite dependencies:
  - For Flutter/mobile: `sqflite: ^2.3.4`
  - For desktop/testing: `sqflite_common_ffi: ^2.3.4+4`
- This change provides better platform flexibility and follows SQLite package best practices

## 1.0.0

### Initial Release

- **Declarative Schema Definition**: Fluent builder pattern for defining database schemas
- **Automatic Migration**: Create missing tables and indices automatically  
- **SQLite Data Types**: Full support for SQLite affinities (INTEGER, REAL, TEXT, BLOB)
- **Column Constraints**: Support for Primary Key, Unique, and Not Null constraints
- **Index Support**: Single-column and composite indices with unique option
- **Migration Planning**: Preview changes before applying them
- **Schema Validation**: Validate schema definitions before migration
- **Type Safety**: Built with null safety and immutable builders
- **Comprehensive Testing**: Unit tests and integration tests with real SQLite databases

### Features

- `SchemaBuilder` - Main entry point for defining database schemas
- `TableBuilder` - Fluent interface for defining table structure
- `ColumnBuilder` - Define columns with constraints and default values
- `IndexBuilder` - Create single and composite indices
- `SchemaMigrator` - Handle database migration operations
- Support for all SQLite data type affinities
- Automatic table and index creation
- Migration planning and validation
