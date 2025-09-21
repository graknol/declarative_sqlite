import 'dart:io';
import 'dart:typed_data';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/files/filesystem_file_repository.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'in_memory_file_repository.dart';

void main() {
  // Initialize FFI for testing
  sqfliteFfiInit();

  group('FileSet Garbage Collection', () {
    late DeclarativeDatabase db;
    late InMemoryFileRepository inMemoryRepo;
    late Directory tempDir;
    late FilesystemFileRepository filesystemRepo;

    setUp(() async {
      // Set up in-memory database with in-memory file repository
      inMemoryRepo = InMemoryFileRepository();
      db = DeclarativeDatabase.inMemory(fileRepository: inMemoryRepo);
      await db.initializeDatabase();

      // Set up temporary directory for filesystem tests
      tempDir = await Directory.systemTemp.createTemp('fileset_gc_test_');
      filesystemRepo = FilesystemFileRepository(tempDir.path);
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('In-Memory Repository', () {
      test('garbageCollectFilesets removes orphaned filesets', () async {
        // Create some files in different filesets
        await db.files.addFile('fileset1', 'file1.txt', Uint8List.fromList([1, 2, 3]));
        await db.files.addFile('fileset2', 'file2.txt', Uint8List.fromList([4, 5, 6]));
        await db.files.addFile('fileset3', 'file3.txt', Uint8List.fromList([7, 8, 9]));

        // Manually add an orphaned fileset to the repository (not in database)
        await inMemoryRepo.addFile('orphaned1', 'orphan1.txt', Stream.value([10, 11, 12]));
        await inMemoryRepo.addFile('orphaned2', 'orphan2.txt', Stream.value([13, 14, 15]));

        // Verify orphaned filesets exist
        expect(inMemoryRepo._files.containsKey('orphaned1'), isTrue);
        expect(inMemoryRepo._files.containsKey('orphaned2'), isTrue);

        // Run garbage collection
        final removedCount = await db.files.garbageCollectFilesets();

        // Verify orphaned filesets were removed
        expect(removedCount, equals(2));
        expect(inMemoryRepo._files.containsKey('orphaned1'), isFalse);
        expect(inMemoryRepo._files.containsKey('orphaned2'), isFalse);

        // Verify valid filesets remain
        expect(inMemoryRepo._files.containsKey('fileset1'), isTrue);
        expect(inMemoryRepo._files.containsKey('fileset2'), isTrue);
        expect(inMemoryRepo._files.containsKey('fileset3'), isTrue);
      });

      test('garbageCollectFilesInFileset removes orphaned files', () async {
        // Create some files in a fileset
        final fileId1 = await db.files.addFile('test_fileset', 'file1.txt', Uint8List.fromList([1, 2, 3]));
        final fileId2 = await db.files.addFile('test_fileset', 'file2.txt', Uint8List.fromList([4, 5, 6]));

        // Manually add orphaned files to the repository (not in database)
        await inMemoryRepo.addFile('test_fileset', 'orphan1', Stream.value([10, 11, 12]));
        await inMemoryRepo.addFile('test_fileset', 'orphan2', Stream.value([13, 14, 15]));

        // Verify orphaned files exist
        final filesetFiles = inMemoryRepo._files['test_fileset']!;
        expect(filesetFiles.containsKey('orphan1'), isTrue);
        expect(filesetFiles.containsKey('orphan2'), isTrue);

        // Run garbage collection on the fileset
        final removedCount = await db.files.garbageCollectFilesInFileset('test_fileset');

        // Verify orphaned files were removed
        expect(removedCount, equals(2));
        expect(filesetFiles.containsKey('orphan1'), isFalse);
        expect(filesetFiles.containsKey('orphan2'), isFalse);

        // Verify valid files remain
        expect(filesetFiles.containsKey(fileId1), isTrue);
        expect(filesetFiles.containsKey(fileId2), isTrue);
      });

      test('garbageCollectAll performs comprehensive cleanup', () async {
        // Create some files in different filesets
        await db.files.addFile('fileset1', 'file1.txt', Uint8List.fromList([1, 2, 3]));
        await db.files.addFile('fileset2', 'file2.txt', Uint8List.fromList([4, 5, 6]));

        // Add orphaned filesets
        await inMemoryRepo.addFile('orphaned1', 'orphan1.txt', Stream.value([10, 11, 12]));
        await inMemoryRepo.addFile('orphaned2', 'orphan2.txt', Stream.value([13, 14, 15]));

        // Add orphaned files in valid filesets
        await inMemoryRepo.addFile('fileset1', 'orphan_file1', Stream.value([16, 17, 18]));
        await inMemoryRepo.addFile('fileset2', 'orphan_file2', Stream.value([19, 20, 21]));

        // Run comprehensive garbage collection
        final result = await db.files.garbageCollectAll();

        // Verify results
        expect(result['filesets'], equals(2)); // orphaned1, orphaned2
        expect(result['files'], equals(2)); // orphan_file1, orphan_file2

        // Verify cleanup
        expect(inMemoryRepo._files.containsKey('orphaned1'), isFalse);
        expect(inMemoryRepo._files.containsKey('orphaned2'), isFalse);
        expect(inMemoryRepo._files['fileset1']?.containsKey('orphan_file1'), isFalse);
        expect(inMemoryRepo._files['fileset2']?.containsKey('orphan_file2'), isFalse);
      });

      test('garbage collection with additional valid filesets/files', () async {
        // Create a file in database
        await db.files.addFile('fileset1', 'file1.txt', Uint8List.fromList([1, 2, 3]));

        // Add filesets/files that should be preserved via additional valid lists
        await inMemoryRepo.addFile('preserve_fileset', 'preserve_file', Stream.value([10, 11, 12]));
        await inMemoryRepo.addFile('fileset1', 'preserve_file_in_valid_fileset', Stream.value([13, 14, 15]));

        // Add truly orphaned items
        await inMemoryRepo.addFile('orphaned_fileset', 'orphan.txt', Stream.value([16, 17, 18]));
        await inMemoryRepo.addFile('fileset1', 'orphan_file', Stream.value([19, 20, 21]));

        // Run garbage collection with additional valid items
        final filesetResult = await db.files.garbageCollectFilesets(
          additionalValidFilesets: ['preserve_fileset'],
        );
        final fileResult = await db.files.garbageCollectFilesInFileset(
          'fileset1',
          additionalValidFiles: ['preserve_file_in_valid_fileset'],
        );

        // Verify preservation and cleanup
        expect(filesetResult, equals(1)); // Only orphaned_fileset removed
        expect(fileResult, equals(1)); // Only orphan_file removed

        expect(inMemoryRepo._files.containsKey('preserve_fileset'), isTrue);
        expect(inMemoryRepo._files.containsKey('orphaned_fileset'), isFalse);
        expect(inMemoryRepo._files['fileset1']?.containsKey('preserve_file_in_valid_fileset'), isTrue);
        expect(inMemoryRepo._files['fileset1']?.containsKey('orphan_file'), isFalse);
      });

      test('garbage collection handles empty scenarios gracefully', () async {
        // Test with no files at all
        final result1 = await db.files.garbageCollectFilesets();
        expect(result1, equals(0));

        final result2 = await db.files.garbageCollectFilesInFileset('nonexistent');
        expect(result2, equals(0));

        final result3 = await db.files.garbageCollectAll();
        expect(result3['filesets'], equals(0));
        expect(result3['files'], equals(0));
      });
    });

    group('Filesystem Repository', () {
      test('garbageCollectFilesets removes orphaned directories', () async {
        final filesystemDb = DeclarativeDatabase.inMemory(fileRepository: filesystemRepo);
        await filesystemDb.initializeDatabase();

        try {
          // Create some files through the database
          await filesystemDb.files.addFile('fileset1', 'file1.txt', Uint8List.fromList([1, 2, 3]));
          await filesystemDb.files.addFile('fileset2', 'file2.txt', Uint8List.fromList([4, 5, 6]));

          // Manually create orphaned directories
          final orphanedDir1 = Directory(p.join(tempDir.path, 'orphaned1'));
          final orphanedDir2 = Directory(p.join(tempDir.path, 'orphaned2'));
          await orphanedDir1.create();
          await orphanedDir2.create();
          await File(p.join(orphanedDir1.path, 'orphan.txt')).writeAsBytes([10, 11, 12]);
          await File(p.join(orphanedDir2.path, 'orphan.txt')).writeAsBytes([13, 14, 15]);

          // Verify orphaned directories exist
          expect(await orphanedDir1.exists(), isTrue);
          expect(await orphanedDir2.exists(), isTrue);

          // Run garbage collection
          final removedCount = await filesystemDb.files.garbageCollectFilesets();

          // Verify orphaned directories were removed
          expect(removedCount, equals(2));
          expect(await orphanedDir1.exists(), isFalse);
          expect(await orphanedDir2.exists(), isFalse);

          // Verify valid directories remain
          expect(await Directory(p.join(tempDir.path, 'fileset1')).exists(), isTrue);
          expect(await Directory(p.join(tempDir.path, 'fileset2')).exists(), isTrue);
        } finally {
          await filesystemDb.close();
        }
      });

      test('garbageCollectFiles removes orphaned files', () async {
        final filesystemDb = DeclarativeDatabase.inMemory(fileRepository: filesystemRepo);
        await filesystemDb.initializeDatabase();

        try {
          // Create some files through the database
          final fileId1 = await filesystemDb.files.addFile('test_fileset', 'file1.txt', Uint8List.fromList([1, 2, 3]));
          final fileId2 = await filesystemDb.files.addFile('test_fileset', 'file2.txt', Uint8List.fromList([4, 5, 6]));

          // Manually create orphaned files
          final filesetDir = Directory(p.join(tempDir.path, 'test_fileset'));
          final orphanFile1 = File(p.join(filesetDir.path, 'orphan1.txt'));
          final orphanFile2 = File(p.join(filesetDir.path, 'orphan2.txt'));
          await orphanFile1.writeAsBytes([10, 11, 12]);
          await orphanFile2.writeAsBytes([13, 14, 15]);

          // Verify orphaned files exist
          expect(await orphanFile1.exists(), isTrue);
          expect(await orphanFile2.exists(), isTrue);

          // Run garbage collection on the fileset
          final removedCount = await filesystemDb.files.garbageCollectFilesInFileset('test_fileset');

          // Verify orphaned files were removed
          expect(removedCount, equals(2));
          expect(await orphanFile1.exists(), isFalse);
          expect(await orphanFile2.exists(), isFalse);

          // Verify valid files remain
          expect(await File(p.join(filesetDir.path, fileId1)).exists(), isTrue);
          expect(await File(p.join(filesetDir.path, fileId2)).exists(), isTrue);
        } finally {
          await filesystemDb.close();
        }
      });

      test('handles cleanup errors gracefully', () async {
        final filesystemDb = DeclarativeDatabase.inMemory(fileRepository: filesystemRepo);
        await filesystemDb.initializeDatabase();

        try {
          // Create a valid file
          await filesystemDb.files.addFile('fileset1', 'file1.txt', Uint8List.fromList([1, 2, 3]));

          // Create a directory that simulates a permission error scenario
          // We'll test this by creating an empty directory structure
          final orphanedDir = Directory(p.join(tempDir.path, 'orphaned_with_issues'));
          await orphanedDir.create();

          // Run garbage collection - should handle any errors gracefully
          final removedCount = await filesystemDb.files.garbageCollectFilesets();

          // Should have attempted to remove the orphaned directory
          expect(removedCount, greaterThanOrEqualTo(1));
        } finally {
          await filesystemDb.close();
        }
      });
    });
  });
}