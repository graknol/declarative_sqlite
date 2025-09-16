import 'dart:async';
import 'dart:typed_data';

import 'package:declarative_sqlite/src/database.dart';
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
}
