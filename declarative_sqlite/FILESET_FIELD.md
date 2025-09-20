# FilesetField Implementation

This document explains the FilesetField implementation for automatic mapping of fileset columns to specialized objects.

## Overview

The `FilesetField` class provides automatic mapping of fileset columns to a special object that contains references to both the database and file repository. This simplifies interactions with filesets and their files by providing a type-safe, convenient API.

## Key Components

### 1. FilesetField Class

The `FilesetField` class (`src/files/fileset_field.dart`) wraps a fileset identifier and provides convenient access to file operations:

```dart
class FilesetField {
  // Core methods
  Future<String> addFile(String fileName, Uint8List content)
  Future<Uint8List?> getFileContent(String fileId) 
  Future<void> deleteFile(String fileId)
  Future<List<Map<String, dynamic>>> getFiles()
  Future<int> getFileCount()
  
  // Properties
  String? get filesetId
  bool get hasValue
  
  // Conversion
  String? toDatabaseValue()
  static FilesetField.fromDatabaseValue(dynamic value, DeclarativeDatabase database)
}
```

### 2. DataMappingUtils

The `DataMappingUtils` class (`src/data_mapping.dart`) provides helper methods for converting between database values and FilesetField instances:

```dart
class DataMappingUtils {
  static FilesetField? filesetFieldFromValue(dynamic value, DeclarativeDatabase database)
  static String? filesetFieldToValue(FilesetField? field)
}
```

### 3. Integration with Generated Code

The FilesetField is designed to be used in generated data classes (via `declarative_sqlite_generator`):

```dart
class DocumentsData {
  final FilesetField attachments;  // Required fileset
  final FilesetField? gallery;     // Optional fileset
  
  static DocumentsData fromMap(Map<String, dynamic> map, DeclarativeDatabase database) {
    return DocumentsData(
      attachments: DataMappingUtils.filesetFieldFromValue(map['attachments'], database)!,
      gallery: DataMappingUtils.filesetFieldFromValue(map['gallery'], database),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'attachments': DataMappingUtils.filesetFieldToValue(attachments),
      'gallery': DataMappingUtils.filesetFieldToValue(gallery),
    };
  }
}
```

## Usage Patterns

### Basic File Operations

```dart
final document = DocumentsData.fromMap(dbRow, database);

// Add files
final fileId = await document.attachments.addFile('report.pdf', pdfBytes);

// List files
final files = await document.attachments.getFiles();
print('Found ${files.length} attachments');

// Get file content
final content = await document.attachments.getFileContent(fileId);

// Delete files
await document.attachments.deleteFile(fileId);
```

### Handling Optional Filesets

```dart
// Check if optional fileset has a value
if (document.gallery?.hasValue == true) {
  final imageCount = await document.gallery!.getFileCount();
  print('Gallery contains $imageCount images');
}
```

### Safe Operations

```dart
// FilesetField handles null/empty values safely
final field = FilesetField.fromDatabaseValue(null, database);
print(field.hasValue); // false
print(await field.getFiles()); // []
print(await field.getFileCount()); // 0

// Throws StateError for operations that need a value
try {
  await field.addFile('test.txt', content); // Throws StateError
} catch (e) {
  print('Cannot add to null fileset: $e');
}
```

## Generator Integration

The `declarative_sqlite_generator` package should be updated to:

1. **Detect fileset columns**: When generating data classes, identify columns with `logicalType: 'fileset'`

2. **Generate FilesetField types**: 
   - Required fileset columns → `FilesetField`
   - Optional fileset columns → `FilesetField?`

3. **Generate conversion methods**:
   - Use `DataMappingUtils.filesetFieldFromValue()` in `fromMap()`
   - Use `DataMappingUtils.filesetFieldToValue()` in `toMap()`

4. **Require database parameter**: The `fromMap()` method should require a `DeclarativeDatabase` parameter

## Benefits

1. **Type Safety**: Fileset columns are now strongly typed as `FilesetField` instead of raw strings
2. **Convenience**: Direct access to file operations without manual FileSet instance management  
3. **Null Safety**: Proper handling of null/empty fileset values
4. **Immutability**: FilesetField instances are immutable and safe to pass around
5. **Consistency**: Follows existing patterns in the declarative_sqlite library

## Migration Guide

For existing code using raw fileset strings:

### Before
```dart
// Manual fileset management
final filesetId = row['attachments'] as String?;
if (filesetId != null) {
  final fileId = await db.files.addFile(filesetId, 'document.pdf', content);
  final files = await db.queryTable('__files', where: 'fileset = ?', whereArgs: [filesetId]);
}
```

### After  
```dart
// Automatic FilesetField mapping
final attachments = DataMappingUtils.filesetFieldFromValue(row['attachments'], db);
if (attachments?.hasValue == true) {
  final fileId = await attachments!.addFile('document.pdf', content);
  final files = await attachments.getFiles();
}
```

Or with generated data classes:
```dart
final document = DocumentsData.fromMap(row, db);
final fileId = await document.attachments.addFile('document.pdf', content);
final files = await document.attachments.getFiles();
```

## Testing

The implementation includes comprehensive tests:

- **Unit tests** (`test/fileset_field_test.dart`): Test FilesetField methods in isolation
- **Integration tests** (`test/fileset_field_integration_test.dart`): Test end-to-end workflows
- **Example usage** (`example/fileset_field_example.dart`): Demonstrate practical usage patterns

Run tests with:
```bash
flutter test test/fileset_field_test.dart
flutter test test/fileset_field_integration_test.dart
```