# Automatic Fileset Column Mapping Implementation

## Overview

This implementation adds automatic mapping of fileset columns to specialized `FilesetField` objects that provide convenient access to file operations while maintaining references to both the database and file repository.

## Problem Solved

**Before**: Fileset columns were stored as plain TEXT values in the database, requiring manual management of the FileSet instance and fileset identifiers.

**After**: Fileset columns are automatically mapped to `FilesetField` objects that provide a clean, type-safe API for file operations.

## Implementation Details

### Core Components

1. **`FilesetField` class** (`lib/src/files/fileset_field.dart`)
   - Wraps fileset identifiers with convenient API
   - Provides file operations: add, get, delete, list, count
   - Handles null/empty values safely
   - Immutable and thread-safe

2. **`DataMappingUtils` class** (`lib/src/data_mapping.dart`)
   - Helper methods for database value conversion
   - `filesetFieldFromValue()` - create FilesetField from DB value
   - `filesetFieldToValue()` - convert FilesetField to DB value

3. **Enhanced `FileSet` class** (`lib/src/files/fileset.dart`)
   - Added `getFilesInFileset()` and `getFileCountInFileset()` methods
   - Better performance for fileset-specific operations

### API Reference

#### FilesetField Methods
```dart
// File operations
Future<String> addFile(String fileName, Uint8List content)
Future<Uint8List?> getFileContent(String fileId)
Future<void> deleteFile(String fileId)

// Listing and counting
Future<List<Map<String, dynamic>>> getFiles()
Future<int> getFileCount()
Future<Map<String, dynamic>?> getFileMetadata(String fileId)

// Properties
String? get filesetId
bool get hasValue

// Conversion
String? toDatabaseValue()
factory FilesetField.fromDatabaseValue(dynamic value, DeclarativeDatabase database)
```

#### DataMappingUtils Methods
```dart
static FilesetField? filesetFieldFromValue(dynamic value, DeclarativeDatabase database)
static String? filesetFieldToValue(FilesetField? field)
```

## Usage Patterns

### Generated Data Classes
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

### File Operations
```dart
final document = DocumentsData.fromMap(dbRow, database);

// Add files
final fileId = await document.attachments.addFile('report.pdf', pdfBytes);

// List files with metadata
final files = await document.attachments.getFiles();
for (final file in files) {
  print('File: ${file['name']}, Size: ${file['size']} bytes');
}

// Get file count efficiently
final count = await document.attachments.getFileCount();

// Get specific file metadata
final metadata = await document.attachments.getFileMetadata(fileId);

// Handle optional filesets
if (document.gallery?.hasValue == true) {
  final images = await document.gallery!.getFiles();
}
```

## Integration with Generator

The `declarative_sqlite_generator` package should be updated to:

1. **Detect fileset columns**: Check for `logicalType: 'fileset'` in table definitions
2. **Generate FilesetField types**: Map to `FilesetField` (required) or `FilesetField?` (optional)
3. **Update fromMap/toMap**: Use `DataMappingUtils` methods for conversion
4. **Add database parameter**: Include `DeclarativeDatabase` parameter in `fromMap()` method

Example generator output:
```dart
// For: table.fileset('attachments', (col) => col.notNull())
final FilesetField attachments;

// For: table.fileset('gallery') 
final FilesetField? gallery;

// In fromMap():
attachments: DataMappingUtils.filesetFieldFromValue(map['attachments'], database)!,
gallery: DataMappingUtils.filesetFieldFromValue(map['gallery'], database),

// In toMap():
'attachments': DataMappingUtils.filesetFieldToValue(attachments),
'gallery': DataMappingUtils.filesetFieldToValue(gallery),
```

## Testing

Comprehensive test coverage includes:

1. **Unit Tests** (`test/fileset_field_test.dart`):
   - FilesetField creation and properties
   - File operations (add, get, delete)
   - Null/empty value handling
   - Conversion methods
   - Equality and toString

2. **Integration Tests** (`test/fileset_field_integration_test.dart`):
   - End-to-end database workflows
   - Real file operations with repository
   - Data mapping round-trips
   - Error handling scenarios

## Files Added/Modified

### New Files
- `lib/src/files/fileset_field.dart` - Core FilesetField implementation
- `test/fileset_field_test.dart` - Unit tests
- `test/fileset_field_integration_test.dart` - Integration tests  
- `example/fileset_field_example.dart` - Usage examples
- `FILESET_FIELD.md` - Detailed documentation

### Modified Files
- `lib/declarative_sqlite.dart` - Added exports
- `lib/src/data_mapping.dart` - Added DataMappingUtils
- `lib/src/files/fileset.dart` - Added convenience methods

## Benefits

1. **Type Safety**: Strong typing for fileset columns
2. **Convenience**: Direct file operations without manual FileSet management
3. **Null Safety**: Proper handling of optional filesets
4. **Performance**: Optimized queries for fileset operations
5. **Immutability**: Safe, immutable field objects
6. **Consistency**: Follows existing library patterns

## Migration

Existing code using raw fileset strings can migrate gradually:

### Before
```dart
final filesetId = row['attachments'] as String?;
if (filesetId != null) {
  await db.files.addFile(filesetId, 'doc.pdf', content);
}
```

### After
```dart
final attachments = DataMappingUtils.filesetFieldFromValue(row['attachments'], db);
if (attachments?.hasValue == true) {
  await attachments!.addFile('doc.pdf', content);
}
```

### With Generated Classes
```dart
final document = DocumentsData.fromMap(row, db);
await document.attachments.addFile('doc.pdf', content);
```

## Conclusion

This implementation provides a clean, type-safe solution for automatic fileset column mapping that simplifies file operations while maintaining the existing architecture and patterns of the declarative_sqlite library.