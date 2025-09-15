import 'package:meta/meta.dart';

/// Represents a file attached to a record in a fileset column.
/// Contains metadata about the file and its synchronization status.
@immutable
class FileAttachment {
  const FileAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.size,
    this.localPath,
    this.remotePath,
    this.syncStatus = FileSyncStatus.pending,
    this.uploadedAt,
    this.checksum,
  });

  /// Unique identifier for this file attachment
  final String id;
  
  /// Original filename
  final String filename;
  
  /// MIME type of the file (e.g., 'image/jpeg', 'application/pdf')
  final String mimeType;
  
  /// File size in bytes
  final int size;
  
  /// Local file path (if file is stored locally)
  final String? localPath;
  
  /// Remote file path or URL (after synchronization)
  final String? remotePath;
  
  /// Current synchronization status
  final FileSyncStatus syncStatus;
  
  /// Timestamp when file was uploaded to remote storage
  final DateTime? uploadedAt;
  
  /// File checksum for integrity verification
  final String? checksum;

  /// Creates a copy of this FileAttachment with updated properties
  FileAttachment copyWith({
    String? id,
    String? filename,
    String? mimeType,
    int? size,
    String? localPath,
    String? remotePath,
    FileSyncStatus? syncStatus,
    DateTime? uploadedAt,
    String? checksum,
  }) {
    return FileAttachment(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      syncStatus: syncStatus ?? this.syncStatus,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      checksum: checksum ?? this.checksum,
    );
  }

  /// Converts this FileAttachment to a JSON-serializable map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'mimeType': mimeType,
      'size': size,
      if (localPath != null) 'localPath': localPath,
      if (remotePath != null) 'remotePath': remotePath,
      'syncStatus': syncStatus.name,
      if (uploadedAt != null) 'uploadedAt': uploadedAt!.toIso8601String(),
      if (checksum != null) 'checksum': checksum,
    };
  }

  /// Creates a FileAttachment from a JSON map
  factory FileAttachment.fromJson(Map<String, dynamic> json) {
    return FileAttachment(
      id: json['id'] as String,
      filename: json['filename'] as String,
      mimeType: json['mimeType'] as String,
      size: json['size'] as int,
      localPath: json['localPath'] as String?,
      remotePath: json['remotePath'] as String?,
      syncStatus: FileSyncStatus.values.firstWhere(
        (status) => status.name == json['syncStatus'],
        orElse: () => FileSyncStatus.pending,
      ),
      uploadedAt: json['uploadedAt'] != null 
          ? DateTime.parse(json['uploadedAt'] as String)
          : null,
      checksum: json['checksum'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileAttachment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          filename == other.filename &&
          mimeType == other.mimeType &&
          size == other.size &&
          localPath == other.localPath &&
          remotePath == other.remotePath &&
          syncStatus == other.syncStatus &&
          uploadedAt == other.uploadedAt &&
          checksum == other.checksum;

  @override
  int get hashCode =>
      id.hashCode ^
      filename.hashCode ^
      mimeType.hashCode ^
      size.hashCode ^
      localPath.hashCode ^
      remotePath.hashCode ^
      syncStatus.hashCode ^
      uploadedAt.hashCode ^
      checksum.hashCode;

  @override
  String toString() => 'FileAttachment(id: $id, filename: $filename, mimeType: $mimeType, size: $size, syncStatus: $syncStatus)';
}

/// Synchronization status for file attachments
enum FileSyncStatus {
  /// File is waiting to be uploaded
  pending,
  
  /// File is currently being uploaded
  uploading,
  
  /// File has been successfully uploaded
  synchronized,
  
  /// File upload failed
  failed,
  
  /// File exists only locally (won't be synchronized)
  localOnly,
}

/// Represents a collection of file attachments stored in a fileset column.
/// Provides methods to manage files and their synchronization status.
@immutable
class Fileset {
  const Fileset({
    this.files = const [],
  });

  /// List of file attachments in this fileset
  final List<FileAttachment> files;

  /// Creates an empty fileset
  static const Fileset empty = Fileset();

  /// Number of files in this fileset
  int get count => files.length;

  /// Whether this fileset is empty
  bool get isEmpty => files.isEmpty;

  /// Whether this fileset has any files
  bool get isNotEmpty => files.isNotEmpty;

  /// Gets all files with a specific sync status
  List<FileAttachment> getFilesByStatus(FileSyncStatus status) {
    return files.where((file) => file.syncStatus == status).toList();
  }

  /// Gets files that need to be synchronized (pending or failed)
  List<FileAttachment> get pendingFiles => 
      files.where((file) => file.syncStatus == FileSyncStatus.pending || 
                           file.syncStatus == FileSyncStatus.failed).toList();

  /// Gets files that are currently being uploaded
  List<FileAttachment> get uploadingFiles => getFilesByStatus(FileSyncStatus.uploading);

  /// Gets successfully synchronized files
  List<FileAttachment> get synchronizedFiles => getFilesByStatus(FileSyncStatus.synchronized);

  /// Adds a new file to this fileset
  Fileset addFile(FileAttachment file) {
    return Fileset(files: [...files, file]);
  }

  /// Removes a file from this fileset by ID
  Fileset removeFile(String fileId) {
    return Fileset(files: files.where((file) => file.id != fileId).toList());
  }

  /// Updates a file in this fileset
  Fileset updateFile(String fileId, FileAttachment updatedFile) {
    return Fileset(
      files: files.map((file) => file.id == fileId ? updatedFile : file).toList(),
    );
  }

  /// Updates the sync status of a file
  Fileset updateFileStatus(String fileId, FileSyncStatus newStatus) {
    return Fileset(
      files: files.map((file) => 
        file.id == fileId ? file.copyWith(syncStatus: newStatus) : file
      ).toList(),
    );
  }

  /// Finds a file by its ID
  FileAttachment? findFile(String fileId) {
    try {
      return files.firstWhere((file) => file.id == fileId);
    } catch (e) {
      return null;
    }
  }

  /// Converts this Fileset to a JSON-serializable map
  Map<String, dynamic> toJson() {
    return {
      'files': files.map((file) => file.toJson()).toList(),
    };
  }

  /// Creates a Fileset from a JSON map
  factory Fileset.fromJson(Map<String, dynamic> json) {
    final filesList = json['files'] as List<dynamic>? ?? [];
    return Fileset(
      files: filesList
          .map((fileJson) => FileAttachment.fromJson(fileJson as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Fileset &&
          runtimeType == other.runtimeType &&
          _listEquals(files, other.files);

  @override
  int get hashCode => files.hashCode;

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'Fileset(files: ${files.length})';
}

/// Callback function type for file upload operations
typedef FileUploadCallback = Future<String> Function(FileAttachment file);

/// Callback function type for file download operations
typedef FileDownloadCallback = Future<String> Function(FileAttachment file);

/// Callback function type for file deletion operations
typedef FileDeleteCallback = Future<void> Function(FileAttachment file);

/// Configuration for fileset column synchronization callbacks
@immutable
class FilesetSyncConfig {
  const FilesetSyncConfig({
    this.onUpload,
    this.onDownload,
    this.onDelete,
    this.autoSync = false,
    this.maxFileSize,
    this.allowedMimeTypes,
  });

  /// Callback invoked when a file needs to be uploaded to remote storage
  /// Should return the remote path/URL of the uploaded file
  final FileUploadCallback? onUpload;

  /// Callback invoked when a file needs to be downloaded from remote storage
  /// Should return the local path where the file was saved
  final FileDownloadCallback? onDownload;

  /// Callback invoked when a file needs to be deleted from remote storage
  final FileDeleteCallback? onDelete;

  /// Whether files should be automatically synchronized
  final bool autoSync;

  /// Maximum allowed file size in bytes
  final int? maxFileSize;

  /// List of allowed MIME types (if null, all types are allowed)
  final List<String>? allowedMimeTypes;

  /// Validates if a file is allowed based on configuration
  bool isFileAllowed(FileAttachment file) {
    if (maxFileSize != null && file.size > maxFileSize!) {
      return false;
    }
    
    if (allowedMimeTypes != null && !allowedMimeTypes!.contains(file.mimeType)) {
      return false;
    }
    
    return true;
  }
}