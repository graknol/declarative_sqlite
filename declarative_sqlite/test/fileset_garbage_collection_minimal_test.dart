import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'in_memory_file_repository.dart';

void main() {
  // Initialize FFI for testing
  sqfliteFfiInit();

  group('Fileset Garbage Collection Basic Tests', () {
    late DeclarativeDatabase db;
    late InMemoryFileRepository fileRepo;

    setUp(() async {
      fileRepo = InMemoryFileRepository();
      db = DeclarativeDatabase.inMemory(fileRepository: fileRepo);
      await db.initializeDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('garbageCollectFilesets method exists and works', () async {
      // Add a file to create a valid fileset
      await db.files.addFile('test_fileset', 'test_file.txt', Uint8List.fromList([1, 2, 3]));
      
      // Manually add an orphaned fileset
      await fileRepo.addFile('orphaned', 'orphan.txt', Stream.value([4, 5, 6]));
      
      // Run garbage collection
      final result = await db.files.garbageCollectFilesets();
      
      // Should have removed 1 orphaned fileset
      expect(result, equals(1));
      expect(fileRepo._files.containsKey('orphaned'), isFalse);
      expect(fileRepo._files.containsKey('test_fileset'), isTrue);
    });

    test('garbageCollectFilesInFileset method exists and works', () async {
      // Add a file to create a valid fileset
      final validFileId = await db.files.addFile('test_fileset', 'valid.txt', Uint8List.fromList([1, 2, 3]));
      
      // Manually add an orphaned file
      await fileRepo.addFile('test_fileset', 'orphan.txt', Stream.value([4, 5, 6]));
      
      // Run garbage collection on the fileset
      final result = await db.files.garbageCollectFilesInFileset('test_fileset');
      
      // Should have removed 1 orphaned file
      expect(result, equals(1));
      expect(fileRepo._files['test_fileset']?.containsKey('orphan.txt'), isFalse);
      expect(fileRepo._files['test_fileset']?.containsKey(validFileId), isTrue);
    });

    test('garbageCollectAll method exists and works', () async {
      // Add valid content
      await db.files.addFile('valid_fileset', 'valid.txt', Uint8List.fromList([1, 2, 3]));
      
      // Add orphaned content
      await fileRepo.addFile('orphaned_fileset', 'orphan1.txt', Stream.value([4, 5, 6]));
      await fileRepo.addFile('valid_fileset', 'orphan2.txt', Stream.value([7, 8, 9]));
      
      // Run comprehensive garbage collection
      final result = await db.files.garbageCollectAll();
      
      // Verify results
      expect(result, isA<Map<String, int>>());
      expect(result.containsKey('filesets'), isTrue);
      expect(result.containsKey('files'), isTrue);
      expect(result['filesets'], equals(1)); // orphaned_fileset
      expect(result['files'], equals(1)); // orphan2.txt
    });
  });
}