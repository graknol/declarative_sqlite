---
sidebar_position: 5
---

# 📁 File Management

`declarative_sqlite` provides a robust, integrated system for managing file attachments associated with your database records. This is useful for any application that needs to store user-generated content like images, documents, or other binary data.

The system is designed around a `fileset` column type and consists of three main components:
1.  **`fileset` Column**: A special column type that stores a unique ID for a collection of files.
2.  **`IFileRepository`**: An abstraction for the physical storage of file content (e.g., local filesystem).
3.  **`FilesetField`**: A convenient wrapper for interacting with a fileset in your data models.

## 1. Defining a `fileset` Column

First, add a `fileset` column to your table definition in your schema.

```dart title="lib/database/schema.dart"
builder.table('documents', (table) {
  table.guid('id').notNull();
  table.text('title').notNull();
  // A fileset column to hold attachments
  table.fileset('attachments');
  table.key(['id']).primary();
});
```

Behind the scenes, the library creates a `_files` metadata table to track individual files and their association with a fileset.

## 2. Configuring the File Repository

You need to tell `DeclarativeDatabase` where to physically store the file content by providing an `IFileRepository`. The library includes a default implementation, `FilesystemFileRepository`, which stores files in a directory on the local filesystem.

```dart
// In a Flutter app, you can use path_provider to get a safe directory
final docsDir = await getApplicationDocumentsDirectory();
final filesDir = Directory(path.join(docsDir.path, 'attachments'));

final database = DeclarativeDatabase(
  path: 'app.db',
  schema: appSchema,
  // Provide the file repository
  fileRepository: FilesystemFileRepository(rootPath: filesDir.path),
);
```

## 3. Using `FilesetField` in Your Model

`FilesetField` is the primary way you'll interact with a fileset. It's a wrapper around the fileset ID that provides methods for adding, retrieving, and deleting files.

If you're using the code generator, a `FilesetField` property will be automatically generated for your `fileset` column.

```dart title="lib/models/document.dart"
part 'document.db.dart';

@GenerateDbRecord('documents')
class Document extends DbRecord {
  Document(super.data, super.database) : super(tableName: 'documents');

  factory Document.fromDbRecord(DbRecord record) {
    return _Document.fromDbRecord(record);
  }

  // The generator creates this property for you
  // FilesetField get attachments => get('attachments');
}
```

### Adding a File

To add a file to a fileset, use the `addFile` method. It takes a filename and the file's binary content (`Uint8List`). It returns the unique ID of the newly created file record.

```dart
// Assume 'doc' is an instance of your Document model
final Uint8List pdfBytes = await File('path/to/report.pdf').readAsBytes();

final fileId = await doc.attachments.addFile('report.pdf', pdfBytes);
```

### Retrieving Files

- `getFiles()`: Returns a list of `FileEntry` objects, which contain metadata about each file in the set (ID, filename, size, etc.).
- `getFileContent(fileId)`: Returns the binary content (`Uint8List`) of a specific file.

```dart
// Get the list of file metadata
final List<FileEntry> fileEntries = await doc.attachments.getFiles();

for (final entry in fileEntries) {
  print('File: ${entry.filename}, Size: ${entry.contentLength} bytes');

  // Get the content of the first file
  if (entry == fileEntries.first) {
    final Uint8List content = await doc.attachments.getFileContent(entry.id);
    // Now you can display the image, save it, etc.
  }
}
```

### Deleting a File

Use the `deleteFile` method with the file's ID to remove it from the fileset and delete its content from the repository.

```dart
await doc.attachments.deleteFile(fileId);
```

## Garbage Collection

When a database record is deleted, its fileset ID is left behind, and the associated files become "orphaned." `declarative_sqlite` includes a built-in garbage collection task to clean up these orphaned files.

You can run this task manually or schedule it to run periodically.

```dart
// Manually trigger garbage collection
await database.maintenanceTasks.runFileGarbageCollection();

// You can also schedule it using the TaskScheduler
scheduler.schedule(
  database.maintenanceTasks.fileGarbageCollectionTask,
  TaskPriority.low,
);
```

This ensures that your application doesn't accumulate unused files over time, saving storage space.

## Next Steps

Learn how to keep your local database in sync with a remote server.

- **Next**: [Data Synchronization](./data-synchronization.md)
