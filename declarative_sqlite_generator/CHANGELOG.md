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