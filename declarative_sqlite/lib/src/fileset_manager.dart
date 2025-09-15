import 'dart:io';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:sqflite_common/sqflite.dart';

/// Manages file storage and metadata for fileset columns.
/// 
/// This class handles:
/// - Creating and managing a common fileset metadata table
/// - Storing actual files on the filesystem with GUID filenames
/// - Managing file metadata and synchronization status
@immutable
class FilesetManager {
  const FilesetManager({
    required this.database,
    required this.storageDirectory,
    this.filesetTableName = '_filesets',
  });

  /// Database connection for storing file metadata
  final Database database;
  
  /// Directory where files are stored on the filesystem
  final String storageDirectory;
  
  /// Name of the table that stores fileset metadata
  final String filesetTableName;

  /// UUID generator for creating file GUIDs
  static const Uuid _uuid = Uuid();

  /// Initializes the fileset management system.
  /// Creates the fileset metadata table if it doesn't exist.
  Future<void> initialize() async {
    await _createFilesetTable();
    await _ensureStorageDirectory();
  }

  /// Creates the fileset metadata table
  Future<void> _createFilesetTable() async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $filesetTableName (
        id TEXT PRIMARY KEY,
        original_filename TEXT NOT NULL,
        storage_filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        checksum TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        local_path TEXT,
        remote_path TEXT,
        uploaded_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // Create index for faster lookups
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_${filesetTableName}_sync_status 
      ON $filesetTableName (sync_status)
    ''');
  }

  /// Ensures the storage directory exists
  Future<void> _ensureStorageDirectory() async {
    final dir = Directory(storageDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Creates a new fileset entry and stores the file.
  /// Returns the fileset ID that should be stored in the column.
  Future<String> addFile({
    required String originalFilename,
    required String sourceFilePath,
    required String mimeType,
    String? checksum,
  }) async {
    final filesetId = _uuid.v4();
    final storageFilename = '${_uuid.v4()}${path.extension(originalFilename)}';
    final targetPath = path.join(storageDirectory, storageFilename);

    // Copy file to storage directory
    final sourceFile = File(sourceFilePath);
    final targetFile = File(targetPath);
    await sourceFile.copy(targetPath);

    // Get file size
    final fileSize = await targetFile.length();

    // Insert metadata into database
    await database.insert(filesetTableName, {
      'id': filesetId,
      'original_filename': originalFilename,
      'storage_filename': storageFilename,
      'mime_type': mimeType,
      'file_size': fileSize,
      'checksum': checksum,
      'sync_status': 'pending',
      'local_path': targetPath,
    });

    return filesetId;
  }

  /// Retrieves file metadata by fileset ID
  Future<FilesetMetadata?> getFile(String filesetId) async {
    final result = await database.query(
      filesetTableName,
      where: 'id = ?',
      whereArgs: [filesetId],
    );

    if (result.isEmpty) return null;

    return FilesetMetadata.fromMap(result.first);
  }

  /// Retrieves all files for multiple fileset IDs
  Future<List<FilesetMetadata>> getFiles(List<String> filesetIds) async {
    if (filesetIds.isEmpty) return [];

    final placeholders = List.filled(filesetIds.length, '?').join(',');
    final result = await database.query(
      filesetTableName,
      where: 'id IN ($placeholders)',
      whereArgs: filesetIds,
    );

    return result.map((row) => FilesetMetadata.fromMap(row)).toList();
  }

  /// Updates file sync status
  Future<void> updateSyncStatus(String filesetId, String syncStatus, {
    String? remotePath,
    DateTime? uploadedAt,
  }) async {
    final updateData = <String, dynamic>{
      'sync_status': syncStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (remotePath != null) {
      updateData['remote_path'] = remotePath;
    }
    
    if (uploadedAt != null) {
      updateData['uploaded_at'] = uploadedAt.toIso8601String();
    }

    await database.update(
      filesetTableName,
      updateData,
      where: 'id = ?',
      whereArgs: [filesetId],
    );
  }

  /// Removes a file from both filesystem and database
  Future<void> removeFile(String filesetId) async {
    final metadata = await getFile(filesetId);
    if (metadata == null) return;

    // Delete file from filesystem
    if (metadata.localPath != null) {
      final file = File(metadata.localPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // Remove from database
    await database.delete(
      filesetTableName,
      where: 'id = ?',
      whereArgs: [filesetId],
    );
  }

  /// Gets the actual file for reading/writing
  File getFileHandle(String filesetId, String storageFilename) {
    final filePath = path.join(storageDirectory, storageFilename);
    return File(filePath);
  }
}

/// Represents file metadata stored in the fileset table
@immutable
class FilesetMetadata {
  const FilesetMetadata({
    required this.id,
    required this.originalFilename,
    required this.storageFilename,
    required this.mimeType,
    required this.fileSize,
    required this.syncStatus,
    this.checksum,
    this.localPath,
    this.remotePath,
    this.uploadedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String originalFilename;
  final String storageFilename;
  final String mimeType;
  final int fileSize;
  final String syncStatus;
  final String? checksum;
  final String? localPath;
  final String? remotePath;
  final DateTime? uploadedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FilesetMetadata.fromMap(Map<String, dynamic> map) {
    return FilesetMetadata(
      id: map['id'] as String,
      originalFilename: map['original_filename'] as String,
      storageFilename: map['storage_filename'] as String,
      mimeType: map['mime_type'] as String,
      fileSize: map['file_size'] as int,
      syncStatus: map['sync_status'] as String,
      checksum: map['checksum'] as String?,
      localPath: map['local_path'] as String?,
      remotePath: map['remote_path'] as String?,
      uploadedAt: map['uploaded_at'] != null 
          ? DateTime.parse(map['uploaded_at'] as String)
          : null,
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null 
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'original_filename': originalFilename,
      'storage_filename': storageFilename,
      'mime_type': mimeType,
      'file_size': fileSize,
      'sync_status': syncStatus,
      if (checksum != null) 'checksum': checksum,
      if (localPath != null) 'local_path': localPath,
      if (remotePath != null) 'remote_path': remotePath,
      if (uploadedAt != null) 'uploaded_at': uploadedAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilesetMetadata &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FilesetMetadata(id: $id, filename: $originalFilename, size: $fileSize)';
}