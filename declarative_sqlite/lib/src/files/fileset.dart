import 'dart:async';
import 'dart:typed_data';

import 'package:declarative_sqlite/src/declarative_database.dart';
import 'package:uuid/uuid.dart';

/// Orchestrates file storage and metadata for fileset columns.
class FileSet {
  final DeclarativeDatabase _db;

  FileSet(this._db);

  /// Adds a file to a fileset.
  ///
  /// This creates a record in the `__files` table and stores the file
  /// using the configured [IFileRepository].
  ///
  /// Returns the ID of the newly created file record.
  Future<String> addFile(
    String fileset,
    String fileName,
    Uint8List content,
  ) async {
    final fileId = Uuid().v4();
    final now = _db.hlcClock.now();

    // Store the file content using the repository
    await _db.fileRepository.addFile(fileset, fileId, Stream.value(content));

    // Store the metadata in the database
    await _db.insert('__files', {
      'id': fileId,
      'fileset': fileset,
      'name': fileName,
      'size': content.length,
      'created_at': now.toString(),
      'modified_at': now.toString(),
    });

    return fileId;
  }

  /// Retrieves the content of a file.
  Future<Uint8List?> getFileContent(String fileId) async {
    final fileRecord = await _db.queryTable(
      '__files',
      where: 'id = ?',
      whereArgs: [fileId],
    );

    if (fileRecord.isEmpty) {
      return null;
    }

    final fileset = fileRecord.first['fileset'] as String;
    final contentStream =
        await _db.fileRepository.getFileContent(fileset, fileId);

    final completer = Completer<Uint8List>();
    final builder = BytesBuilder();
    contentStream.listen(
      builder.add,
      onDone: () => completer.complete(builder.toBytes()),
      onError: completer.completeError,
    );
    return completer.future;
  }

  /// Deletes a file from a fileset.
  ///
  /// This removes the file from the [IFileRepository] and deletes its
  /// metadata record from the `__files` table.
  Future<void> deleteFile(String fileId) async {
    final fileRecord = await _db.queryTable(
      '__files',
      where: 'id = ?',
      whereArgs: [fileId],
    );

    if (fileRecord.isNotEmpty) {
      final fileset = fileRecord.first['fileset'] as String;
      await _db.fileRepository.removeFile(fileset, fileId);
      await _db.delete('__files', where: 'id = ?', whereArgs: [fileId]);
    }
  }

  /// Gets all files in a specific fileset.
  ///
  /// Returns a list of file metadata records from the `__files` table
  /// for the given fileset.
  Future<List<Map<String, dynamic>>> getFilesInFileset(String fileset) async {
    return await _db.queryTable(
      '__files',
      where: 'fileset = ?',
      whereArgs: [fileset],
      orderBy: 'created_at DESC',
    );
  }

  /// Gets the count of files in a specific fileset.
  ///
  /// Returns the number of files in the given fileset.
  Future<int> getFileCountInFileset(String fileset) async {
    final result = await _db.queryTable(
      '__files',
      columns: ['COUNT(*) as count'],
      where: 'fileset = ?',
      whereArgs: [fileset],
    );
    return result.first['count'] as int;
  }

  /// Performs garbage collection on fileset directories.
  ///
  /// This method identifies and removes orphaned fileset directories from the
  /// file repository. Orphaned filesets are those that exist on disk but have
  /// no corresponding records in the database.
  ///
  /// Optionally, you can provide [additionalValidFilesets] to preserve specific
  /// filesets that might not be in the database but should be kept.
  ///
  /// Returns the number of orphaned filesets that were removed.
  Future<int> garbageCollectFilesets({
    List<String> additionalValidFilesets = const [],
  }) async {
    // Get all filesets referenced in the database
    final filesetRecords = await _db.queryTable(
      '__files',
      columns: ['DISTINCT fileset'],
    );

    final validFilesets = <String>{
      ...filesetRecords.map((record) => record['fileset'] as String),
      ...additionalValidFilesets,
    };

    return await _db.fileRepository.garbageCollectFilesets(validFilesets.toList());
  }

  /// Performs garbage collection on files within a specific fileset.
  ///
  /// This method identifies and removes orphaned files from the specified
  /// fileset directory. Orphaned files are those that exist on disk but have
  /// no corresponding records in the database.
  ///
  /// [fileset] is the fileset ID to clean up.
  /// Optionally, you can provide [additionalValidFiles] to preserve specific
  /// files that might not be in the database but should be kept.
  ///
  /// Returns the number of orphaned files that were removed.
  Future<int> garbageCollectFilesInFileset(
    String fileset, {
    List<String> additionalValidFiles = const [],
  }) async {
    // Get all file IDs in this fileset from the database
    final fileRecords = await _db.queryTable(
      '__files',
      columns: ['id'],
      where: 'fileset = ?',
      whereArgs: [fileset],
    );

    final validFiles = <String>{
      ...fileRecords.map((record) => record['id'] as String),
      ...additionalValidFiles,
    };

    return await _db.fileRepository.garbageCollectFiles(fileset, validFiles.toList());
  }

  /// Performs a comprehensive garbage collection on both filesets and files.
  ///
  /// This is a convenience method that first cleans up orphaned filesets,
  /// then cleans up orphaned files within the remaining valid filesets.
  ///
  /// Returns a map with 'filesets' and 'files' keys indicating the number
  /// of orphaned items removed in each category.
  Future<Map<String, int>> garbageCollectAll() async {
    int removedFilesets = 0;
    int removedFiles = 0;

    // First, clean up orphaned filesets
    removedFilesets = await garbageCollectFilesets();

    // Then, clean up orphaned files in each remaining valid fileset
    final validFilesetRecords = await _db.queryTable(
      '__files',
      columns: ['DISTINCT fileset'],
    );

    for (final record in validFilesetRecords) {
      final fileset = record['fileset'] as String;
      removedFiles += await garbageCollectFilesInFileset(fileset);
    }

    return {
      'filesets': removedFilesets,
      'files': removedFiles,
    };
  }
}
