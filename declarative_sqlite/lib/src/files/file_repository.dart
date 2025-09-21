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

  /// Performs garbage collection on filesets.
  ///
  /// Removes all fileset directories on disk that are not in the provided
  /// [validFilesetIds] list. This helps clean up orphaned filesets that
  /// may have been left behind when database records were deleted.
  ///
  /// [validFilesetIds] is the list of all valid fileset IDs that should
  /// be preserved. Any fileset directory not in this list will be removed.
  ///
  /// Returns the number of orphaned filesets that were removed.
  Future<int> garbageCollectFilesets(List<String> validFilesetIds);

  /// Performs garbage collection on files within a specific fileset.
  ///
  /// Removes all files on disk in the specified fileset that are not in the
  /// provided [validFileIds] list. This helps clean up orphaned files that
  /// may have been left behind when file records were deleted.
  ///
  /// [filesetId] is the ID of the fileset to clean up.
  /// [validFileIds] is the list of all valid file IDs that should be
  /// preserved within this fileset. Any file not in this list will be removed.
  ///
  /// Returns the number of orphaned files that were removed.
  Future<int> garbageCollectFiles(String filesetId, List<String> validFileIds);
}
