import 'package:declarative_sqlite/declarative_sqlite.dart';

/// A specialized field type for fileset columns that simplifies file management.
/// 
/// This class wraps the Fileset functionality and provides convenient methods
/// for working with file attachments in generated data classes.
class FilesetField {
  const FilesetField._({
    required this.fileset,
    required this.manager,
  });

  /// The underlying fileset containing file IDs
  final Fileset fileset;
  
  /// The fileset manager for file operations
  final FilesetManager manager;

  /// Creates an empty fileset field
  static FilesetField empty(FilesetManager manager) {
    return FilesetField._(
      fileset: Fileset.empty,
      manager: manager,
    );
  }

  /// Creates a fileset field from a database value
  static FilesetField fromDatabaseValue(String? value, FilesetManager manager) {
    return FilesetField._(
      fileset: Fileset.fromDatabaseValue(value),
      manager: manager,
    );
  }

  /// Creates a fileset field from an existing Fileset
  static FilesetField fromFileset(Fileset fileset, FilesetManager manager) {
    return FilesetField._(
      fileset: fileset,
      manager: manager,
    );
  }

  /// Number of files in this fileset
  int get count => fileset.count;

  /// Whether this fileset is empty
  bool get isEmpty => fileset.isEmpty;

  /// Whether this fileset has any files
  bool get isNotEmpty => fileset.isNotEmpty;

  /// List of fileset IDs
  List<String> get filesetIds => fileset.filesetIds;

  /// Loads all file attachments
  Future<List<FileAttachment>> loadFiles() async {
    return await fileset.loadFiles(manager);
  }

  /// Gets files that need to be synchronized (pending or failed)
  Future<List<FileAttachment>> getPendingFiles() async {
    return await fileset.getPendingFiles(manager);
  }

  /// Gets files that are currently being uploaded
  Future<List<FileAttachment>> getUploadingFiles() async {
    return await fileset.getUploadingFiles(manager);
  }

  /// Gets successfully synchronized files
  Future<List<FileAttachment>> getSynchronizedFiles() async {
    return await fileset.getSynchronizedFiles(manager);
  }

  /// Adds a new file ID to this fileset (returns new instance)
  FilesetField addFilesetId(String filesetId) {
    return FilesetField._(
      fileset: fileset.addFilesetId(filesetId),
      manager: manager,
    );
  }

  /// Removes a file ID from this fileset (returns new instance)
  FilesetField removeFilesetId(String filesetId) {
    return FilesetField._(
      fileset: fileset.removeFilesetId(filesetId),
      manager: manager,
    );
  }

  /// Checks if this fileset contains a specific file ID
  bool containsFilesetId(String filesetId) {
    return fileset.containsFilesetId(filesetId);
  }

  /// Adds a new file from a file path and returns updated fileset field
  Future<FilesetField> addFile({
    required String originalFilename,
    required String sourceFilePath,
    required String mimeType,
    String? checksum,
  }) async {
    final filesetId = await manager.addFile(
      originalFilename: originalFilename,
      sourceFilePath: sourceFilePath,
      mimeType: mimeType,
      checksum: checksum,
    );
    
    return addFilesetId(filesetId);
  }

  /// Removes a file from both the fileset and storage
  Future<FilesetField> removeFile(String filesetId) async {
    if (containsFilesetId(filesetId)) {
      await manager.removeFile(filesetId);
      return removeFilesetId(filesetId);
    }
    return this;
  }

  /// Updates the sync status of a file
  Future<void> updateSyncStatus(String filesetId, String syncStatus, {
    String? remotePath,
    DateTime? uploadedAt,
  }) async {
    await manager.updateSyncStatus(
      filesetId, 
      syncStatus,
      remotePath: remotePath,
      uploadedAt: uploadedAt,
    );
  }

  /// Converts this fileset field to a database-storable value
  String toDatabaseValue() {
    return fileset.toDatabaseValue();
  }

  /// Gets a specific file by ID
  Future<FileAttachment?> getFile(String filesetId) async {
    if (!containsFilesetId(filesetId)) return null;
    
    final metadata = await manager.getFile(filesetId);
    if (metadata == null) return null;
    
    return FileAttachment.fromMetadata(metadata);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilesetField &&
          runtimeType == other.runtimeType &&
          fileset == other.fileset;

  @override
  int get hashCode => fileset.hashCode;

  @override
  String toString() => 'FilesetField(count: $count)';
}