import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/files/filesystem_file_repository.dart';
import 'package:path/path.dart' as p;

/// Example demonstrating fileset garbage collection functionality.
/// 
/// This example shows how to use the garbage collection methods to clean up
/// orphaned files and filesets from disk storage.
void main() async {
  // Create a temporary directory for file storage
  final tempDir = await Directory.systemTemp.createTemp('fileset_gc_example_');
  print('Using storage directory: ${tempDir.path}');

  try {
    // Create database with filesystem file repository
    final fileRepository = FilesystemFileRepository(tempDir.path);
    final db = DeclarativeDatabase.inMemory(fileRepository: fileRepository);
    await db.initializeDatabase();

    await demonstrateFilesetGarbageCollection(db, tempDir);
  } finally {
    // Clean up
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<void> demonstrateFilesetGarbageCollection(
  DeclarativeDatabase db,
  Directory storageDir,
) async {
  print('\n=== Fileset Garbage Collection Demo ===\n');

  // Step 1: Create some legitimate files through the database
  print('1. Creating legitimate files through database...');
  
  final fileId1 = await db.files.addFile(
    'user_uploads', 
    'document1.pdf', 
    Uint8List.fromList('PDF content for document 1'.codeUnits),
  );
  print('   Created file: $fileId1 in user_uploads');
  
  final fileId2 = await db.files.addFile(
    'user_uploads', 
    'image1.jpg', 
    Uint8List.fromList('JPEG content for image 1'.codeUnits),
  );
  print('   Created file: $fileId2 in user_uploads');
  
  final fileId3 = await db.files.addFile(
    'temp_files', 
    'temp1.txt', 
    Uint8List.fromList('Temporary file content'.codeUnits),
  );
  print('   Created file: $fileId3 in temp_files');

  // Step 2: Manually create orphaned files and filesets
  // (simulating what might happen if files are left behind after database cleanup)
  print('\n2. Creating orphaned files and filesets...');
  
  // Create orphaned fileset directories
  final orphanedFileset1 = Directory(p.join(storageDir.path, 'orphaned_fileset_1'));
  final orphanedFileset2 = Directory(p.join(storageDir.path, 'orphaned_fileset_2'));
  await orphanedFileset1.create();
  await orphanedFileset2.create();
  
  // Add files to orphaned filesets
  await File(p.join(orphanedFileset1.path, 'orphan1.txt'))
      .writeAsString('This file is orphaned');
  await File(p.join(orphanedFileset2.path, 'orphan2.txt'))
      .writeAsString('This file is also orphaned');
  print('   Created orphaned fileset: orphaned_fileset_1');
  print('   Created orphaned fileset: orphaned_fileset_2');
  
  // Create orphaned files within valid filesets
  final userUploadsDir = Directory(p.join(storageDir.path, 'user_uploads'));
  await File(p.join(userUploadsDir.path, 'orphan_in_valid_fileset.txt'))
      .writeAsString('Orphaned file in valid fileset');
  print('   Created orphaned file in user_uploads: orphan_in_valid_fileset.txt');

  // Step 3: Show current state
  print('\n3. Current storage state:');
  await showStorageState(storageDir);

  // Step 4: Demonstrate fileset garbage collection
  print('\n4. Running fileset garbage collection...');
  
  final removedFilesets = await db.files.garbageCollectFilesets();
  print('   Removed $removedFilesets orphaned filesets');

  // Step 5: Demonstrate file garbage collection within a fileset
  print('\n5. Running file garbage collection for user_uploads...');
  
  final removedFiles = await db.files.garbageCollectFilesInFileset('user_uploads');
  print('   Removed $removedFiles orphaned files from user_uploads');

  // Step 6: Show state after cleanup
  print('\n6. Storage state after garbage collection:');
  await showStorageState(storageDir);

  // Step 7: Demonstrate comprehensive garbage collection
  print('\n7. Demonstrating comprehensive garbage collection...');
  
  // First, create some more orphaned items
  final orphanedFileset3 = Directory(p.join(storageDir.path, 'another_orphan'));
  await orphanedFileset3.create();
  await File(p.join(orphanedFileset3.path, 'file.txt')).writeAsString('Orphan');
  
  await File(p.join(userUploadsDir.path, 'another_orphan_file.dat'))
      .writeAsString('Another orphan file');

  // Run comprehensive cleanup
  final result = await db.files.garbageCollectAll();
  print('   Comprehensive cleanup results:');
  print('     - Removed ${result['filesets']} orphaned filesets');
  print('     - Removed ${result['files']} orphaned files');

  // Step 8: Demonstrate preservation of specific files
  print('\n8. Demonstrating preservation with additional valid items...');
  
  // Create items that should be preserved
  final preserveFileset = Directory(p.join(storageDir.path, 'preserve_me'));
  await preserveFileset.create();
  await File(p.join(preserveFileset.path, 'important.txt'))
      .writeAsString('This should be preserved');
  
  await File(p.join(userUploadsDir.path, 'preserve_this_file.txt'))
      .writeAsString('This file should be preserved too');

  // Run garbage collection with preservation
  final preservedFilesets = await db.files.garbageCollectFilesets(
    additionalValidFilesets: ['preserve_me'],
  );
  print('   Filesets removed (with preservation): $preservedFilesets');
  
  final preservedFiles = await db.files.garbageCollectFilesInFileset(
    'user_uploads',
    additionalValidFiles: ['preserve_this_file.txt'],
  );
  print('   Files removed from user_uploads (with preservation): $preservedFiles');

  // Step 9: Final state
  print('\n9. Final storage state:');
  await showStorageState(storageDir);

  // Step 10: Demonstrate scheduled cleanup
  print('\n10. Setting up scheduled cleanup (demo)...');
  await demonstrateScheduledCleanup(db);

  await db.close();
}

/// Shows the current state of files and directories in storage.
Future<void> showStorageState(Directory storageDir) async {
  if (!await storageDir.exists()) {
    print('   Storage directory does not exist');
    return;
  }

  await for (final entity in storageDir.list()) {
    if (entity is Directory) {
      final filesetName = p.basename(entity.path);
      print('   Fileset: $filesetName');
      
      await for (final file in entity.list()) {
        if (file is File) {
          final fileName = p.basename(file.path);
          final size = await file.length();
          print('     - $fileName ($size bytes)');
        }
      }
    }
  }
}

/// Demonstrates how to set up scheduled garbage collection.
Future<void> demonstrateScheduledCleanup(DeclarativeDatabase db) async {
  // Example of a cleanup function that could be called periodically
  Future<void> performScheduledCleanup() async {
    try {
      print('   Running scheduled cleanup...');
      final result = await db.files.garbageCollectAll();
      
      final totalCleaned = result['filesets']! + result['files']!;
      if (totalCleaned > 0) {
        print('   Scheduled cleanup completed:');
        print('     - Removed ${result['filesets']} orphaned filesets');
        print('     - Removed ${result['files']} orphaned files');
      } else {
        print('   No orphaned items found during scheduled cleanup');
      }
    } catch (e) {
      print('   Scheduled cleanup failed: $e');
    }
  }

  // Simulate running the cleanup (in a real app, you'd use Timer.periodic)
  await performScheduledCleanup();
  
  print('   In a real application, you would set up periodic cleanup like:');
  print('   Timer.periodic(Duration(days: 1), (_) => performScheduledCleanup());');
}

/// Example of a maintenance mode cleanup.
Future<void> maintenanceModeCleanup(DeclarativeDatabase db) async {
  print('Starting maintenance mode cleanup...');
  
  try {
    // Get current counts before cleanup
    final allFilesets = await db.queryTable('__files', columns: ['DISTINCT fileset']);
    print('Found ${allFilesets.length} filesets in database');
    
    // Perform comprehensive cleanup
    final result = await db.files.garbageCollectAll();
    
    print('Maintenance cleanup completed:');
    print('  - Removed ${result['filesets']} orphaned filesets');
    print('  - Removed ${result['files']} orphaned files');
    
    // Verify integrity
    for (final record in allFilesets) {
      final fileset = record['fileset'] as String;
      final fileCount = await db.files.getFileCountInFileset(fileset);
      print('  - Fileset "$fileset" has $fileCount files');
    }
    
  } catch (e) {
    print('Maintenance cleanup failed: $e');
    rethrow;
  }
}

/// Example of selective cleanup for specific operations.
Future<void> selectiveCleanupExample(DeclarativeDatabase db) async {
  // After processing a batch of user uploads
  print('Processing batch uploads...');
  
  // ... upload processing logic ...
  
  // Clean up any orphaned files that might have been left during processing
  final cleaned = await db.files.garbageCollectFilesInFileset('batch_uploads');
  if (cleaned > 0) {
    print('Cleaned up $cleaned orphaned files from batch processing');
  }
  
  // For very large operations, you might want to clean up periodically
  // during the operation to prevent disk space issues
}