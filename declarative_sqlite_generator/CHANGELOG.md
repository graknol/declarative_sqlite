## 1.2.0

### Updates
- Updated to use declarative_sqlite ^1.2.0
- Enhanced compatibility with unified save() method
- Generated code now works seamlessly with the new unified save() approach

## 1.1.1

### Bug Fixes
- Fixed the getHlc issue in generated code

## 1.1.0

### Features
- **LWW-Only Setter Generation**: Enhanced code generation to only create setters for LWW (Last-Write-Wins) columns
  - Provides compile-time safety against accidentally updating non-LWW columns on server-origin rows
  - Non-LWW columns get read-only getters with helpful documentation comments
  - Generated setters automatically use the appropriate typed setter methods (`setText`, `setInteger`, etc.)
- **Enhanced Documentation**: Generated code includes helpful comments explaining why certain columns don't have setters

### Code Generation Improvements
- Improved column analysis to distinguish between LWW and non-LWW columns
- Enhanced generated code documentation for better developer experience
- Updated to work with declarative_sqlite ^1.1.0 non-LWW column protection features

## 1.0.2

### Updates
- Updated to use declarative_sqlite ^1.0.2
- Aligned with foreign key removal changes

## 1.0.1

### Updates
- Updated to use declarative_sqlite ^1.0.1
- Added missing dependencies (glob, logging, path) for proper pub.dev publication
- Updated documentation to remove build.yaml requirement

## 1.0.0

### Features
- `@GenerateDbRecord` annotation for generating typed record classes
- `@DbSchema()` annotation for marking schema definition functions
- Automatic discovery of schema functions (no build.yaml required)
- Code generation for typed getters and setters
- Build system integration with `build_runner`

### Code Generation
- Generates `.db.dart` part files with typed accessors
- Type-safe database record operations
- Automatic schema analysis and code generation

### Documentation
- Complete setup guide without build.yaml configuration
- Usage examples with proper annotations
- Integration with DeclarativeSQLite core package