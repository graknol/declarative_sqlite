import 'package:declarative_sqlite/declarative_sqlite.dart';

class InMemoryFileRepository implements IFileRepository {
  final Map<String, List<int>> _files = {};

  @override
  Future<void> deleteFile(String fileId) async {
    _files.remove(fileId);
  }

  @override
  Future<List<int>?> getFile(String fileId) async {
    return _files[fileId];
  }

  @override
  Future<void> saveFile(String fileId, List<int> content) async {
    _files[fileId] = content;
  }
}
