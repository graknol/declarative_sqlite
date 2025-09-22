# Fileset Garbage Collection API

The Declarative SQLite library provides comprehensive garbage collection functionality for filesets and files to help maintain disk space efficiency and remove orphaned data.

## Overview

When files or filesets are deleted from the database but not properly cleaned up from disk storage, they become "orphaned" - they exist on disk but have no corresponding database records. The garbage collection API helps identify and remove these orphaned items.

## Core Methods

### FileSet Garbage Collection

#### `garbageCollectFilesets()`

Removes orphaned fileset directories that exist on disk but have no corresponding files in the database.

```dart
// Clean up all orphaned filesets
final removedCount = await db.files.garbageCollectFilesets();
print('Removed $removedCount orphaned filesets');

// Preserve specific filesets even if they're not in the database
final removedCount = await db.files.garbageCollectFilesets(
  additionalValidFilesets: ['temp_fileset', 'backup_fileset'],
);
```

#### `garbageCollectFilesInFileset()`

Removes orphaned files within a specific fileset that exist on disk but have no corresponding records in the database.

```dart
// Clean up orphaned files in a specific fileset
final removedCount = await db.files.garbageCollectFilesInFileset('user_uploads');
print('Removed $removedCount orphaned files from user_uploads');

// Preserve specific files even if they're not in the database
final removedCount = await db.files.garbageCollectFilesInFileset(
  'user_uploads',
  additionalValidFiles: ['temp_file.txt', 'cache_file.dat'],
);
```

#### `garbageCollectAll()`

Performs comprehensive garbage collection on both filesets and files in a single operation.

```dart
final result = await db.files.garbageCollectAll();
print('Removed ${result['filesets']} orphaned filesets');
print('Removed ${result['files']} orphaned files');
```

## Repository-Level Methods

### IFileRepository Interface

The garbage collection functionality is implemented at the repository level, allowing different storage backends to provide their own cleanup logic.

#### `garbageCollectFilesets(List<String> validFilesetIds)`

Low-level method that removes fileset directories not in the provided valid list.

```dart
// Get valid filesets from database
final validFilesets = await getValidFilesetsFromDatabase();

// Clean up at repository level
final removedCount = await fileRepository.garbageCollectFilesets(validFilesets);
```

#### `garbageCollectFiles(String filesetId, List<String> validFileIds)`

Low-level method that removes files within a fileset that are not in the provided valid list.

```dart
// Get valid files for a fileset from database
final validFiles = await getValidFilesFromDatabase('user_uploads');

// Clean up at repository level
final removedCount = await fileRepository.garbageCollectFiles('user_uploads', validFiles);
```

## Implementation Details

### FilesystemFileRepository

For filesystem-based storage, the garbage collection:

- Walks through the storage directory structure
- Compares existing directories/files with the provided valid lists
- Removes orphaned items using `Directory.delete()` and `File.delete()`
- Handles errors gracefully and continues cleanup even if individual items fail to delete
- Returns the count of successfully removed items

### InMemoryFileRepository

For testing and in-memory scenarios:

- Iterates through the internal file storage map
- Removes entries not present in the valid lists
- Returns the count of removed items

## Best Practices

### Regular Cleanup

Schedule regular garbage collection to prevent accumulation of orphaned files:

```dart
// Daily cleanup job
Timer.periodic(Duration(days: 1), (_) async {
  final result = await db.files.garbageCollectAll();
  logger.info('Cleaned up ${result['filesets']} filesets and ${result['files']} files');
});
```

### Safe Cleanup

Always use the high-level methods (`garbageCollectFilesets`, `garbageCollectFilesInFileset`) rather than the low-level repository methods to ensure proper database synchronization:

```dart
// ✅ Safe - uses database to determine valid items
await db.files.garbageCollectFilesets();

// ❌ Risky - manual list might miss valid items
await fileRepository.garbageCollectFilesets(manualList);
```

### Preserve Important Files

Use the `additionalValid*` parameters to preserve files that might not be in the database but are still needed:

```dart
// Preserve temporary files that are being processed
await db.files.garbageCollectFilesInFileset(
  'processing_queue',
  additionalValidFiles: tempFiles.map((f) => f.id).toList(),
);
```

### Error Handling

The methods handle errors gracefully but you may want to log results:

```dart
try {
  final result = await db.files.garbageCollectAll();
  logger.info('Garbage collection completed: $result');
} catch (e) {
  logger.error('Garbage collection failed: $e');
  // Cleanup will continue for other items even if some fail
}
```

## Use Cases

### Application Shutdown Cleanup

```dart
// Clean up when app shuts down
await db.files.garbageCollectAll();
await db.close();
```

### Maintenance Mode

```dart
// Comprehensive cleanup during maintenance
print('Starting maintenance cleanup...');
final result = await db.files.garbageCollectAll();
print('Cleaned up ${result['filesets']} orphaned filesets');
print('Cleaned up ${result['files']} orphaned files');
print('Maintenance cleanup completed');
```

### Selective Cleanup

```dart
// Clean up specific fileset after batch operations
await processUserUploads();
await db.files.garbageCollectFilesInFileset('user_uploads');
```

### Recovery from Corruption

```dart
// Rebuild file integrity after database recovery
final allFilesets = await db.queryTable('__files', columns: ['DISTINCT fileset']);
for (final record in allFilesets) {
  final fileset = record['fileset'] as String;
  final cleaned = await db.files.garbageCollectFilesInFileset(fileset);
  print('Cleaned $cleaned orphaned files from $fileset');
}
```

## Performance Considerations

- Garbage collection is I/O intensive as it scans the filesystem
- Consider running during off-peak hours for large datasets
- The filesystem scan time scales with the number of files/directories
- Database queries to determine valid items are typically fast with proper indexing

## Error Handling

The garbage collection methods handle common scenarios gracefully:

- **Permission Errors**: Logged but don't stop the cleanup process
- **Missing Directories**: Treated as already cleaned (returns 0)
- **File Lock Errors**: Logged and skipped, cleanup continues
- **Database Errors**: Will throw and stop the operation

All methods return counts of successfully removed items, so partial failures still report accurate cleanup results.