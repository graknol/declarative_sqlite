import 'dart:async';
import 'package:declarative_sqlite/declarative_sqlite.dart';

class InMemoryFileRepository implements IFileRepository {
  final Map<String, Map<String, List<int>>> _files = {};
  final Map<String, bool> _filesets = {};

  @override
  Future<String> addFile(String filesetId, String fileId, Stream<List<int>> content) async {
    _filesets[filesetId] = true;
    _files[filesetId] ??= {};
    final bytes = await content.fold<List<int>>([], (previous, element) => previous + element);
    _files[filesetId]![fileId] = bytes;
    return 'memory://$filesetId/$fileId';
  }

  @override
  Future<Stream<List<int>>> getFileContent(String filesetId, String fileId) async {
    final bytes = _files[filesetId]?[fileId];
    if (bytes == null) throw Exception('File not found: $filesetId/$fileId');
    return Stream.value(bytes);
  }

  @override
  Future<void> removeFile(String filesetId, String fileId) async {
    _files[filesetId]?.remove(fileId);
  }

  @override
  Future<int> garbageCollectFilesets(List<String> validFilesetIds) async {
    int removed = 0;
    final toRemove = _filesets.keys.where((id) => !validFilesetIds.contains(id)).toList();
    for (final filesetId in toRemove) {
      _filesets.remove(filesetId);
      _files.remove(filesetId);
      removed++;
    }
    return removed;
  }

  @override
  Future<int> garbageCollectFiles(String filesetId, List<String> validFileIds) async {
    final fileset = _files[filesetId];
    if (fileset == null) return 0;
    
    int removed = 0;
    final toRemove = fileset.keys.where((id) => !validFileIds.contains(id)).toList();
    for (final fileId in toRemove) {
      fileset.remove(fileId);
      removed++;
    }
    return removed;
  }
}
