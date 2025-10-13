# Generator Tests

This directory contains tests for the declarative_sqlite_generator package.

## Running Tests

```bash
cd declarative_sqlite_generator
dart test
```

## Testing the LWW HLC Column Fix

The `lww_hlc_column_test.dart` file tests that the generator correctly skips `__hlc` columns when generating typed accessors.

### Background

When a column is marked with `.lww()` (Last-Write-Wins), the library automatically creates a companion `__hlc` column to store the Hybrid Logical Clock timestamp for conflict resolution. For example:

```dart
table.text('description').notNull('').lww();
```

This creates two columns:
- `description` - the actual user data
- `description__hlc` - the HLC timestamp (internal use only)

### The Fix

The generator now skips these `__hlc` columns when generating typed properties, because:
1. They are internal implementation details for synchronization
2. There are no `getHlc`/`setHlc` methods on `DbRecord` to access them
3. Users should not directly manipulate these columns

The fix is in `lib/src/builder.dart` around line 133:

```dart
// Skip HLC columns - they are internal implementation details for LWW sync
if (col.name.endsWith('__hlc')) {
  continue;
}
```

### Manual Testing with the Demo App

You can also test this with the demo app:

1. Update the demo schema to include LWW columns (already done in `demo/lib/schema.dart`)
2. Run the code generator:
   ```bash
   cd demo
   flutter pub get
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
3. Check the generated `*.db.dart` files - they should NOT contain properties for `__hlc` columns
4. The generated code should compile without errors

### What Was Fixed

Before the fix, if you had:
```dart
table.text('description').notNull('').lww();
```

The generator would create:
```dart
String get description => getTextNotNull('description');
set description(String value) => setText('description', value);

Hlc? get descriptionHlc => getHlc('description__hlc'); // ❌ ERROR: getHlc doesn't exist
```

After the fix:
```dart
String get description => getTextNotNull('description');
set description(String value) => setText('description', value);

// ✅ No descriptionHlc accessor generated
```
