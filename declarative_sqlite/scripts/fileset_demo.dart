import 'dart:convert';
import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('=== Fileset Column Type Demonstration (New Architecture) ===');
  
  // Initialize sqflite_ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  try {
    await _demonstrateFilesetUsage();
    print('✓ Fileset column type demonstration completed successfully!');
  } catch (e, stackTrace) {
    print('✗ Error during fileset demonstration: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
  
  print('=== Demonstration Complete ===');
}

Future<void> _demonstrateFilesetUsage() async {
  print('1. Creating schema with fileset columns...');
  
  // Create a schema with fileset columns
  final schema = SchemaBuilder()
      .table('projects', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('name', (col) => col.notNull())
          .text('description')
          .fileset('documents') // Optional document attachments
          .fileset('gallery', (col) => col.notNull())) // Required gallery images
      .table('posts', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .text('content')
          .integer('project_id', (col) => col.notNull())
          .fileset('media_files')); // Optional media attachments

  print('✓ Schema created with fileset columns');

  print('2. Setting up database and file storage...');
  final database = await openDatabase(':memory:');
  final migrator = SchemaMigrator();
  await migrator.migrate(database, schema);
  
  // Create temporary directory for file storage
  final tempDir = '/tmp/fileset_demo_${DateTime.now().millisecondsSinceEpoch}';
  await Directory(tempDir).create(recursive: true);
  
  // Initialize fileset manager
  final filesetManager = FilesetManager(
    database: database,
    storageDirectory: tempDir,
  );
  await filesetManager.initialize();
  
  print('✓ Database migrated with fileset support');
  print('✓ File storage initialized at: $tempDir');

  print('3. Creating test files and adding them to fileset manager...');
  
  // Create some test files
  final reqFile = File('$tempDir/source_requirements.pdf');
  final specFile = File('$tempDir/source_design-spec.docx');
  final mockupFile = File('$tempDir/source_mockup.png');
  final screenshotFile = File('$tempDir/source_screenshot.jpg');
  
  await reqFile.writeAsString('Mock PDF content for requirements document');
  await specFile.writeAsString('Mock DOCX content for design specification');
  await mockupFile.writeAsString('Mock PNG content for UI mockup');
  await screenshotFile.writeAsString('Mock JPG content for screenshot');
  
  // Add files to fileset manager
  final docId1 = await filesetManager.addFile(
    originalFilename: 'requirements.pdf',
    sourceFilePath: reqFile.path,
    mimeType: 'application/pdf',
  );
  
  final docId2 = await filesetManager.addFile(
    originalFilename: 'design-spec.docx',
    sourceFilePath: specFile.path,
    mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  );
  
  final imgId1 = await filesetManager.addFile(
    originalFilename: 'mockup.png',
    sourceFilePath: mockupFile.path,
    mimeType: 'image/png',
  );
  
  final imgId2 = await filesetManager.addFile(
    originalFilename: 'screenshot.jpg',
    sourceFilePath: screenshotFile.path,
    mimeType: 'image/jpeg',
  );
  
  print('✓ Test files created and added to fileset manager');
  print('  - Documents: $docId1, $docId2');
  print('  - Images: $imgId1, $imgId2');

  print('4. Creating filesets and inserting data...');
  final dataAccess = await DataAccess.create(database: database, schema: schema);

  // Create filesets with the IDs
  final projectDocuments = Fileset(filesetIds: [docId1, docId2]);
  final projectGallery = Fileset(filesetIds: [imgId1, imgId2]);

  // Insert project with fileset data
  final projectId = await dataAccess.insert('projects', {
    'name': 'Mobile App Development',
    'description': 'A new mobile application project with file management',
    'documents': projectDocuments.toDatabaseValue(),
    'gallery': projectGallery.toDatabaseValue(),
  });

  print('✓ Project inserted with ID: $projectId');

  // Create media file for post
  final videoFile = File('$tempDir/source_progress-video.mp4');
  await videoFile.writeAsString('Mock MP4 content for progress video');
  
  final mediaId = await filesetManager.addFile(
    originalFilename: 'progress-video.mp4',
    sourceFilePath: videoFile.path,
    mimeType: 'video/mp4',
  );

  final postMediaFiles = Fileset(filesetIds: [mediaId]);

  final postId = await dataAccess.insert('posts', {
    'title': 'Development Progress Update',
    'content': 'Here is the latest progress on our mobile app development...',
    'project_id': projectId,
    'media_files': postMediaFiles.toDatabaseValue(),
  });

  print('✓ Post inserted with ID: $postId');

  print('5. Retrieving and inspecting fileset data...');

  // Retrieve the project
  final retrievedProject = await dataAccess.getByPrimaryKey('projects', projectId);
  print('✓ Retrieved project: ${retrievedProject!['name']}');

  // Parse the documents fileset
  final documentsFileset = Fileset.fromDatabaseValue(retrievedProject['documents'] as String?);
  final documentFiles = await documentsFileset.loadFiles(filesetManager);
  
  print('  Documents in project (${documentFiles.length} files):');
  for (final file in documentFiles) {
    print('    - ${file.filename} (${file.mimeType}, ${_formatFileSize(file.size)}, ${file.syncStatus.name})');
  }

  // Parse the gallery fileset
  final galleryFileset = Fileset.fromDatabaseValue(retrievedProject['gallery'] as String?);
  final galleryFiles = await galleryFileset.loadFiles(filesetManager);
  
  print('  Gallery images in project (${galleryFiles.length} files):');
  for (final file in galleryFiles) {
    print('    - ${file.filename} (${file.mimeType}, ${_formatFileSize(file.size)}, ${file.syncStatus.name})');
  }

  print('6. Demonstrating fileset operations...');

  // Add a new file to the documents
  final manualFile = File('$tempDir/source_user-manual.pdf');
  await manualFile.writeAsString('Mock PDF content for user manual');
  
  final docId3 = await filesetManager.addFile(
    originalFilename: 'user-manual.pdf',
    sourceFilePath: manualFile.path,
    mimeType: 'application/pdf',
  );

  final updatedDocuments = documentsFileset.addFilesetId(docId3);
  print('✓ Added new document to fileset (${updatedDocuments.count} total files)');

  // Update sync status of a file
  await filesetManager.updateSyncStatus(docId1, 'synchronized', 
    remotePath: 'https://storage.example.com/files/$docId1',
    uploadedAt: DateTime.now());
  print('✓ Updated sync status of requirements.pdf to synchronized');

  // Update the project with modified fileset
  await dataAccess.updateByPrimaryKey('projects', projectId, {
    'documents': updatedDocuments.toDatabaseValue(),
  });

  print('✓ Updated project with new document fileset');

  print('7. Demonstrating sync status filtering...');

  // Reload the updated fileset and get files by sync status
  final updatedFileset = Fileset.fromDatabaseValue(
    (await dataAccess.getByPrimaryKey('projects', projectId))!['documents'] as String?
  );
  
  final allFiles = await updatedFileset.loadFiles(filesetManager);
  final pendingFiles = await updatedFileset.getPendingFiles(filesetManager);
  final synchronizedFiles = await updatedFileset.getSynchronizedFiles(filesetManager);

  print('  All files: ${allFiles.length}');
  for (final file in allFiles) {
    print('    - ${file.filename} (${file.syncStatus.name})');
  }

  print('  Pending files: ${pendingFiles.length}');
  for (final file in pendingFiles) {
    print('    - ${file.filename}');
  }

  print('  Synchronized files: ${synchronizedFiles.length}');
  for (final file in synchronizedFiles) {
    print('    - ${file.filename}');
  }

  print('8. Demonstrating file access...');

  // Get file handle for actual file operations
  final firstFile = allFiles.first;
  final metadata = await filesetManager.getFile(firstFile.id);
  if (metadata != null) {
    final fileHandle = filesetManager.getFileHandle(metadata.id, metadata.storageFilename);
    print('  File ${metadata.originalFilename} is stored at: ${fileHandle.path}');
    print('  File exists: ${await fileHandle.exists()}');
    if (await fileHandle.exists()) {
      final content = await fileHandle.readAsString();
      print('  File content preview: ${content.substring(0, content.length.clamp(0, 50))}...');
    }
  }

  print('9. Demonstrating sync configuration...');

  // Create sync configuration
  final syncConfig = FilesetSyncConfig(
    maxFileSize: 5 * 1024 * 1024, // 5MB max
    allowedMimeTypes: [
      'image/jpeg',
      'image/png',
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ],
    autoSync: true,
    onUpload: (file) async {
      print('    Uploading ${file.filename}...');
      await Future.delayed(Duration(milliseconds: 100)); // Simulate upload
      return 'https://storage.example.com/files/${file.id}';
    },
    onDownload: (file) async {
      print('    Downloading ${file.filename}...');
      await Future.delayed(Duration(milliseconds: 50)); // Simulate download
      return '/local/downloads/${file.filename}';
    },
    onDelete: (file) async {
      print('    Deleting ${file.filename} from remote storage...');
      await Future.delayed(Duration(milliseconds: 25)); // Simulate deletion
    },
  );

  // Test file validation
  final validFile = FileAttachment(
    id: 'test1',
    filename: 'test.jpg',
    mimeType: 'image/jpeg',
    size: 1024000, // 1MB
  );

  final invalidFile = FileAttachment(
    id: 'test2',
    filename: 'large-video.mp4',
    mimeType: 'video/mp4',
    size: 10 * 1024 * 1024, // 10MB - too large
  );

  print('  Valid file (test.jpg): ${syncConfig.isFileAllowed(validFile)}');
  print('  Invalid file (large-video.mp4): ${syncConfig.isFileAllowed(invalidFile)}');

  // Simulate sync operations
  if (syncConfig.onUpload != null) {
    final uploadedUrl = await syncConfig.onUpload!(validFile);
    print('  Simulated upload result: $uploadedUrl');
  }

  print('✓ Sync configuration demonstration completed');

  print('10. Cleaning up...');
  await database.close();
  
  // Clean up temp directory
  try {
    await Directory(tempDir).delete(recursive: true);
    print('✓ Temporary files cleaned up');
  } catch (e) {
    print('⚠ Warning: Could not clean up temporary files: $e');
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}