import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:declarative_sqlite/src/files/file_repository.dart';

/// A default implementation of [IFileRepository] that stores files on the
/// local filesystem.
class FilesystemFileRepository implements IFileRepository {
  final String _storagePath;

  /// Creates a new [FilesystemFileRepository].
  ///
  /// [_storagePath] is the root directory where files will be stored.
  FilesystemFileRepository(this._storagePath);

  String _getFolderPath(String filesetId) => p.join(_storagePath, filesetId);
  String _getFilePath(String filesetId, String fileId) =>
      p.join(_getFolderPath(filesetId), fileId);

  @override
  Future<String> addFile(
    String filesetId,
    String fileId,
    Stream<List<int>> content,
  ) async {
    final folderPath = _getFolderPath(filesetId);
    await Directory(folderPath).create(recursive: true);

    final filePath = _getFilePath(filesetId, fileId);
    final file = File(filePath);

    final sink = file.openWrite();
    await content.pipe(sink);
    await sink.close();

    return filePath;
  }

  @override
  Future<void> removeFile(String filesetId, String fileId) async {
    final filePath = _getFilePath(filesetId, fileId);
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<Stream<List<int>>> getFileContent(
      String filesetId, String fileId) async {
    final filePath = _getFilePath(filesetId, fileId);
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found at path: $filePath');
    }
    return file.openRead();
  }

  @override
  Future<int> garbageCollectFilesets(List<String> validFilesetIds) async {
    final storageDir = Directory(_storagePath);
    if (!await storageDir.exists()) {
      return 0; // Nothing to clean up
    }

    final validFilesetSet = validFilesetIds.toSet();
    int removedCount = 0;

    await for (final entity in storageDir.list()) {
      if (entity is Directory) {
        final filesetId = p.basename(entity.path);
        
        // Skip if this fileset ID is valid
        if (validFilesetSet.contains(filesetId)) {
          continue;
        }

        // This is an orphaned fileset directory, remove it
        try {
          await entity.delete(recursive: true);
          removedCount++;
        } catch (e) {
          // Log error but continue with cleanup
          print('Warning: Failed to delete orphaned fileset directory ${entity.path}: $e');
        }
      }
    }

    return removedCount;
  }

  @override
  Future<int> garbageCollectFiles(String filesetId, List<String> validFileIds) async {
    final filesetDir = Directory(_getFolderPath(filesetId));
    if (!await filesetDir.exists()) {
      return 0; // Fileset directory doesn't exist
    }

    final validFileSet = validFileIds.toSet();
    int removedCount = 0;

    await for (final entity in filesetDir.list()) {
      if (entity is File) {
        final fileId = p.basename(entity.path);
        
        // Skip if this file ID is valid
        if (validFileSet.contains(fileId)) {
          continue;
        }

        // This is an orphaned file, remove it
        try {
          await entity.delete();
          removedCount++;
        } catch (e) {
          // Log error but continue with cleanup
          print('Warning: Failed to delete orphaned file ${entity.path}: $e');
        }
      }
    }

    return removedCount;
  }
}
