# Database Recreation Feature

## Overview
Added a `recreateDatabase` parameter to `DeclarativeDatabase.open()` that allows deleting and recreating the database file before opening. This feature is designed for testing scenarios and demo data initialization.

## Usage

### Basic Usage
```dart
// For testing or demo initialization
final db = await DeclarativeDatabase.open(
  'path/to/database.db',
  databaseFactory: databaseFactory,
  schema: schema,
  fileRepository: fileRepository,
  recreateDatabase: true, // Deletes existing database first
);
```

### Typical Use Cases
```dart
// Test setup
await DeclarativeDatabase.open(
  testDbPath,
  databaseFactory: databaseFactory,
  schema: testSchema,
  fileRepository: fileRepository,
  recreateDatabase: true, // Clean slate for each test
);

// Demo app initialization
await DeclarativeDatabase.open(
  demoDbPath,
  databaseFactory: databaseFactory,
  schema: demoSchema,
  fileRepository: fileRepository,
  recreateDatabase: true, // Start fresh with demo data
);
```

## Safety Measures

### Debug Mode Only
The `recreateDatabase` feature **only works in debug mode** as a safety measure:

#### ✅ Debug Mode (Assertions Enabled)
```dart
// This works - database will be deleted and recreated
final db = await DeclarativeDatabase.open(
  path,
  // ... other parameters
  recreateDatabase: true,
);
```

#### ❌ Release Mode (Assertions Disabled)
```dart
// This throws StateError in release mode
final db = await DeclarativeDatabase.open(
  path,
  // ... other parameters
  recreateDatabase: true, // ❌ Will throw StateError
);
```

### Error Messages
In release mode, attempting to use `recreateDatabase: true` will throw:
```
StateError: recreateDatabase=true is not allowed in production/release mode. 
This is a safety measure to prevent accidental data loss.
```

### Read-Only Protection
The feature is also disabled when `isReadOnly: true`:
```dart
// This is ignored (no deletion occurs)
final db = await DeclarativeDatabase.open(
  path,
  // ... other parameters
  isReadOnly: true,
  recreateDatabase: true, // Ignored for read-only databases
);
```

## Implementation Details

### Debug Mode Detection
The implementation uses Dart's assertion mechanism to detect debug mode:
```dart
var debugMode = false;
assert(() {
  debugMode = true; // Only executed when assertions are enabled
  return true;
}());

if (debugMode) {
  // Safe to recreate database
} else {
  // Throw error in release mode
}
```

### Error Handling
- If the database file doesn't exist, deletion is silently ignored
- Only throws errors when trying to use the feature in production
- Preserves all other database opening functionality

## Benefits

### Development Workflow
- **Clean Testing**: Each test run starts with a fresh database
- **Demo Preparation**: Easily reset demo applications to initial state
- **Development Reset**: Quick way to clear development databases

### Production Safety
- **Accidental Protection**: Prevents accidental data loss in production
- **Explicit Intent**: Forces developers to consciously choose database recreation
- **Build-Time Safety**: Protection is enforced at the compilation level

### Backwards Compatibility
- **Optional Parameter**: `recreateDatabase` defaults to `false`
- **Existing Code**: No changes required for existing code
- **Zero Impact**: No performance impact when not used

## Examples

### Unit Testing
```dart
group('User Repository Tests', () {
  late DeclarativeDatabase db;
  
  setUp(() async {
    db = await DeclarativeDatabase.open(
      'test_database.db',
      databaseFactory: databaseFactoryMemory,
      schema: testSchema,
      fileRepository: memoryFileRepository,
      recreateDatabase: true, // Fresh database for each test
    );
  });
  
  test('should create user', () async {
    // Test with clean database state
  });
});
```

### Demo App Initialization
```dart
class DemoApp {
  static Future<DeclarativeDatabase> initializeDatabase() async {
    final db = await DeclarativeDatabase.open(
      'demo_app.db',
      databaseFactory: databaseFactory,
      schema: appSchema,
      fileRepository: fileRepository,
      recreateDatabase: true, // Start with fresh demo data
    );
    
    // Populate with demo data
    await _insertDemoUsers(db);
    await _insertDemoPosts(db);
    
    return db;
  }
}
```

### Development Reset
```dart
// In development tools or admin panels
Future<void> resetDevelopmentDatabase() async {
  await db.close();
  
  final freshDb = await DeclarativeDatabase.open(
    developmentDbPath,
    databaseFactory: databaseFactory,
    schema: schema,
    fileRepository: fileRepository,
    recreateDatabase: true, // Clear all development data
  );
  
  // Reinitialize with seed data
  await initializeSeedData(freshDb);
}
```

This feature provides a safe and convenient way to recreate databases for development and testing purposes while protecting production data through debug-mode-only operation.