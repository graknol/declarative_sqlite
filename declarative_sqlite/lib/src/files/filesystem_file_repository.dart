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
}
