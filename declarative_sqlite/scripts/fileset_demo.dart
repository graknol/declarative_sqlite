import 'dart:convert';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('=== Fileset Column Type Demonstration ===');
  
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

  print('2. Setting up database...');
  final database = await openDatabase(':memory:');
  final migrator = SchemaMigrator();
  await migrator.migrate(database, schema);
  print('✓ Database migrated with fileset support');

  print('3. Creating file attachments...');
  
  // Create some file attachments for demonstration
  final projectDocuments = Fileset(files: [
    FileAttachment(
      id: 'doc1',
      filename: 'requirements.pdf',
      mimeType: 'application/pdf',
      size: 1024000,
      localPath: '/documents/requirements.pdf',
      syncStatus: FileSyncStatus.pending,
    ),
    FileAttachment(
      id: 'doc2',
      filename: 'design-spec.docx',
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      size: 512000,
      localPath: '/documents/design-spec.docx',
      syncStatus: FileSyncStatus.synchronized,
      remotePath: 'https://storage.example.com/docs/design-spec.docx',
      uploadedAt: DateTime.now().subtract(Duration(days: 1)),
    ),
  ]);

  final projectGallery = Fileset(files: [
    FileAttachment(
      id: 'img1',
      filename: 'mockup.png',
      mimeType: 'image/png',
      size: 2048000,
      localPath: '/images/mockup.png',
      syncStatus: FileSyncStatus.uploading,
    ),
    FileAttachment(
      id: 'img2',
      filename: 'screenshot.jpg',
      mimeType: 'image/jpeg',
      size: 1536000,
      localPath: '/images/screenshot.jpg',
      syncStatus: FileSyncStatus.synchronized,
      remotePath: 'https://cdn.example.com/images/screenshot.jpg',
      uploadedAt: DateTime.now().subtract(Duration(hours: 2)),
      checksum: 'sha256:abc123def456',
    ),
  ]);

  print('✓ File attachments created');

  print('4. Inserting data with filesets...');
  final dataAccess = await DataAccess.create(database: database, schema: schema);

  // Insert project with fileset data
  final projectId = await dataAccess.insert('projects', {
    'name': 'Mobile App Development',
    'description': 'A new mobile application project',
    'documents': jsonEncode(projectDocuments.toJson()),
    'gallery': jsonEncode(projectGallery.toJson()),
  });

  print('✓ Project inserted with ID: $projectId');

  // Insert post with media files
  final postMediaFiles = Fileset(files: [
    FileAttachment(
      id: 'media1',
      filename: 'progress-video.mp4',
      mimeType: 'video/mp4',
      size: 10240000,
      localPath: '/videos/progress-video.mp4',
      syncStatus: FileSyncStatus.failed, // Failed upload, needs retry
    ),
  ]);

  final postId = await dataAccess.insert('posts', {
    'title': 'Development Progress Update',
    'content': 'Here is the latest progress on our mobile app development...',
    'project_id': projectId,
    'media_files': jsonEncode(postMediaFiles.toJson()),
  });

  print('✓ Post inserted with ID: $postId');

  print('5. Retrieving and manipulating fileset data...');

  // Retrieve the project
  final retrievedProject = await dataAccess.getByPrimaryKey('projects', projectId);
  print('✓ Retrieved project: ${retrievedProject!['name']}');

  // Parse the documents fileset
  final documentsJson = jsonDecode(retrievedProject['documents'] as String) as Map<String, dynamic>;
  final documentsFileset = Fileset.fromJson(documentsJson);
  
  print('  Documents in project:');
  for (final file in documentsFileset.files) {
    print('    - ${file.filename} (${file.mimeType}, ${_formatFileSize(file.size)}, ${file.syncStatus.name})');
  }

  // Parse the gallery fileset
  final galleryJson = jsonDecode(retrievedProject['gallery'] as String) as Map<String, dynamic>;
  final galleryFileset = Fileset.fromJson(galleryJson);
  
  print('  Gallery images in project:');
  for (final file in galleryFileset.files) {
    print('    - ${file.filename} (${file.mimeType}, ${_formatFileSize(file.size)}, ${file.syncStatus.name})');
  }

  print('6. Demonstrating fileset operations...');

  // Add a new file to the documents
  final newDocument = FileAttachment(
    id: 'doc3',
    filename: 'user-manual.pdf',
    mimeType: 'application/pdf',
    size: 768000,
    localPath: '/documents/user-manual.pdf',
    syncStatus: FileSyncStatus.pending,
  );

  final updatedDocuments = documentsFileset.addFile(newDocument);
  print('✓ Added new document to fileset (${updatedDocuments.count} total files)');

  // Update sync status of a file
  final syncedDocuments = updatedDocuments.updateFileStatus('doc1', FileSyncStatus.synchronized);
  print('✓ Updated sync status of requirements.pdf to synchronized');

  // Update the project with modified fileset
  await dataAccess.updateByPrimaryKey('projects', projectId, {
    'documents': jsonEncode(syncedDocuments.toJson()),
  });

  print('✓ Updated project with new document fileset');

  print('7. Demonstrating sync status filtering...');

  // Get files by sync status
  final pendingFiles = syncedDocuments.pendingFiles;
  final synchronizedFiles = syncedDocuments.synchronizedFiles;
  final uploadingFiles = galleryFileset.uploadingFiles;

  print('  Pending files: ${pendingFiles.length}');
  for (final file in pendingFiles) {
    print('    - ${file.filename}');
  }

  print('  Synchronized files: ${synchronizedFiles.length}');
  for (final file in synchronizedFiles) {
    print('    - ${file.filename}');
  }

  print('  Currently uploading: ${uploadingFiles.length}');
  for (final file in uploadingFiles) {
    print('    - ${file.filename}');
  }

  print('8. Demonstrating sync configuration...');

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

  await database.close();
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}