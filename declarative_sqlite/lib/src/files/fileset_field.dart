import 'dart:async';
import 'dart:typed_data';

import 'package:declarative_sqlite/src/database.dart';
import 'package:declarative_sqlite/src/files/fileset.dart';

/// Represents a fileset column value with convenient access to file operations.
/// 
/// This class wraps a fileset identifier and provides easy access to file
/// operations for that specific fileset through the database's FileSet instance.
class FilesetField {
  final String? _filesetId;
  final DeclarativeDatabase _database;
  late final FileSet _fileSet;

  /// Creates a new FilesetField with the given fileset identifier and database.
  FilesetField._(this._filesetId, this._database) {
    _fileSet = _database.files;
  }

  /// Creates a FilesetField from a database value.
  /// 
  /// [value] should be the fileset identifier (string) from the database.
  /// [database] is the DeclarativeDatabase instance.
  factory FilesetField.fromDatabaseValue(
    dynamic value,
    DeclarativeDatabase database,
  ) {
    final filesetId = value as String?;
    return FilesetField._(filesetId, database);
  }

  /// Gets the fileset identifier.
  String? get filesetId => _filesetId;

  /// Returns true if this fileset field has a value (is not null or empty).
  bool get hasValue => _filesetId != null && _filesetId!.isNotEmpty;

  /// Adds a file to this fileset.
  ///
  /// Returns the ID of the newly created file record.
  /// Throws [StateError] if this fileset field has no value.
  Future<String> addFile(
    String fileName,
    Uint8List content,
  ) async {
    if (!hasValue) {
      throw StateError('Cannot add file to null or empty fileset');
    }
    return await _fileSet.addFile(_filesetId!, fileName, content);
  }

  /// Retrieves the content of a file by its ID.
  /// 
  /// Returns null if the file is not found.
  Future<Uint8List?> getFileContent(String fileId) async {
    return await _fileSet.getFileContent(fileId);
  }

  /// Deletes a file from this fileset.
  /// 
  /// [fileId] is the ID of the file to delete.
  Future<void> deleteFile(String fileId) async {
    await _fileSet.deleteFile(fileId);
  }

  /// Gets all files in this fileset.
  /// 
  /// Returns a list of file metadata maps from the __files table.
  /// Returns an empty list if this fileset field has no value.
  Future<List<Map<String, dynamic>>> getFiles() async {
    if (!hasValue) {
      return [];
    }
    return await _database.queryTable(
      '__files',
      where: 'fileset = ?',
      whereArgs: [_filesetId],
    );
  }

  /// Gets the count of files in this fileset.
  /// 
  /// Returns 0 if this fileset field has no value.
  Future<int> getFileCount() async {
    if (!hasValue) {
      return 0;
    }
    final result = await _database.queryTable(
      '__files',
      columns: ['COUNT(*) as count'],
      where: 'fileset = ?',
      whereArgs: [_filesetId],
    );
    return result.first['count'] as int;
  }

  /// Returns the database value for this fileset field.
  /// 
  /// This is used when converting back to a map for database storage.
  String? toDatabaseValue() => _filesetId;

  @override
  String toString() {
    return 'FilesetField(filesetId: $_filesetId, hasValue: $hasValue)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilesetField && other._filesetId == _filesetId;
  }

  @override
  int get hashCode => _filesetId.hashCode;
}