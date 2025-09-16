import 'dart:async';
import 'dart:typed_data';

import 'package:declarative_sqlite/src/files/file_repository.dart';

/// An in-memory implementation of [IFileRepository] for testing purposes.
class InMemoryFileRepository implements IFileRepository {
  final Map<String, Map<String, Uint8List>> _files = {};

  @override
  Future<String> addFile(
      String fileset, String fileId, Stream<List<int>> contentStream) async {
    final content = await _streamToBytes(contentStream);
    _files.putIfAbsent(fileset, () => {})[fileId] = content;
    return fileId;
  }

  @override
  Future<Stream<List<int>>> getFileContent(
      String fileset, String fileId) async {
    final content = _files[fileset]?[fileId];
    if (content == null) {
      throw Exception('File not found: $fileset/$fileId');
    }
    return Stream.value(content);
  }

  @override
  Future<void> removeFile(String fileset, String fileId) async {
    _files[fileset]?.remove(fileId);
  }

  Future<Uint8List> _streamToBytes(Stream<List<int>> stream) {
    final completer = Completer<Uint8List>();
    final builder = BytesBuilder();
    stream.listen(
      builder.add,
      onDone: () => completer.complete(builder.toBytes()),
      onError: completer.completeError,
    );
    return completer.future;
  }
}
