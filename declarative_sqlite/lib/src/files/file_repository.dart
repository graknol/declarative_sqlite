import 'dart:async';

/// Defines the contract for a file repository used to store and retrieve
/// the content of files.
abstract class IFileRepository {
  /// Adds a file's content to a logical container.
  ///
  /// [filesetId] is the ID of the container (e.g., a folder).
  /// [fileId] is the unique ID of the file (e.g., a filename).
  /// [content] is a stream of the file's byte content.
  ///
  /// Returns the path where the file was stored.
  Future<String> addFile(
    String filesetId,
    String fileId,
    Stream<List<int>> content,
  );

  /// Removes a file's content.
  ///
  /// [filesetId] is the ID of the container.
  /// [fileId] is the ID of the file to remove.
  Future<void> removeFile(String filesetId, String fileId);

  /// Retrieves the content of a specific file.
  ///
  /// [filesetId] is the ID of the container.
  /// [fileId] is the ID of the file to retrieve.
  ///
  /// Returns a stream of the file's byte content.
  Future<Stream<List<int>>> getFileContent(String filesetId, String fileId);
}
