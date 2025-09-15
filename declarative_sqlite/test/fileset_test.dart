import 'dart:convert';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('Fileset Column Type Tests', () {
    late Database database;
    late SchemaMigrator migrator;
    late DataAccess dataAccess;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      database = await openDatabase(':memory:');
      migrator = SchemaMigrator();
    });

    tearDown(() async {
      await database.close();
    });

    test('should support fileset column type in schema definition', () {
      final schema = SchemaBuilder()
          .table('documents', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .fileset('attachments')
              .fileset('gallery', (col) => col.notNull()));

      expect(schema.hasTable('documents'), isTrue);
      
      final table = schema.getTable('documents');
      expect(table, isNotNull);
      
      // Check that fileset columns are present
      final attachmentsColumn = table!.columns.firstWhere((col) => col.name == 'attachments');
      expect(attachmentsColumn.dataType, equals(SqliteDataType.fileset));
      
      final galleryColumn = table.columns.firstWhere((col) => col.name == 'gallery');
      expect(galleryColumn.dataType, equals(SqliteDataType.fileset));
      expect(galleryColumn.constraints.contains(ConstraintType.notNull), isTrue);
    });

    test('should generate correct SQL for fileset columns', () {
      final schema = SchemaBuilder()
          .table('posts', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('content')
              .fileset('media_files', (col) => col.notNull()));

      final sqlStatements = schema.toSqlStatements();
      final createTableStatement = sqlStatements.first;
      
      expect(createTableStatement, contains('media_files TEXT NOT NULL'));
    });

    test('should migrate database with fileset columns', () async {
      final schema = SchemaBuilder()
          .table('projects', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('name', (col) => col.notNull())
              .fileset('documents')
              .fileset('images', (col) => col.notNull()));

      // Migration should succeed
      await migrator.migrate(database, schema);
      
      // Verify table was created
      final result = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='projects'"
      );
      expect(result.length, equals(1));
    });

    test('should support CRUD operations with fileset columns', () async {
      final schema = SchemaBuilder()
          .table('albums', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .fileset('photos'));

      await migrator.migrate(database, schema);
      dataAccess = await DataAccess.create(database: database, schema: schema);

      // Create a fileset with some photos
      final fileset = Fileset(files: [
        FileAttachment(
          id: 'photo1',
          filename: 'vacation.jpg',
          mimeType: 'image/jpeg',
          size: 2048576,
          localPath: '/photos/vacation.jpg',
          syncStatus: FileSyncStatus.pending,
        ),
        FileAttachment(
          id: 'photo2',
          filename: 'landscape.png',
          mimeType: 'image/png',
          size: 1024768,
          localPath: '/photos/landscape.png',
          syncStatus: FileSyncStatus.synchronized,
          remotePath: 'https://example.com/files/landscape.png',
        ),
      ]);

      // Insert album with fileset
      final albumId = await dataAccess.insert('albums', {
        'title': 'Summer Vacation',
        'photos': jsonEncode(fileset.toJson()),
      });

      expect(albumId, isNotNull);

      // Retrieve and verify the data
      final retrievedAlbum = await dataAccess.getByPrimaryKey('albums', albumId);
      expect(retrievedAlbum, isNotNull);
      expect(retrievedAlbum!['title'], equals('Summer Vacation'));
      
      // Parse the fileset data
      final photosJson = jsonDecode(retrievedAlbum['photos'] as String) as Map<String, dynamic>;
      final retrievedFileset = Fileset.fromJson(photosJson);
      
      expect(retrievedFileset.count, equals(2));
      expect(retrievedFileset.files[0].filename, equals('vacation.jpg'));
      expect(retrievedFileset.files[1].filename, equals('landscape.png'));
      expect(retrievedFileset.files[1].syncStatus, equals(FileSyncStatus.synchronized));
    });

    test('should handle empty fileset', () async {
      final schema = SchemaBuilder()
          .table('notes', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('content')
              .fileset('attachments'));

      await migrator.migrate(database, schema);
      dataAccess = await DataAccess.create(database: database, schema: schema);

      // Insert with empty fileset
      final noteId = await dataAccess.insert('notes', {
        'content': 'Simple note without attachments',
        'attachments': jsonEncode(Fileset.empty.toJson()),
      });

      final retrievedNote = await dataAccess.getByPrimaryKey('notes', noteId);
      final attachmentsJson = jsonDecode(retrievedNote!['attachments'] as String) as Map<String, dynamic>;
      final retrievedFileset = Fileset.fromJson(attachmentsJson);
      
      expect(retrievedFileset.isEmpty, isTrue);
      expect(retrievedFileset.count, equals(0));
    });

    test('should validate fileset requires encoding', () {
      expect(SqliteDataType.fileset.requiresEncoding, isTrue);
      expect(SqliteDataType.fileset.sqlName, equals('TEXT'));
    });
  });

  group('FileAttachment Tests', () {
    test('should create FileAttachment with required properties', () {
      final file = FileAttachment(
        id: 'file1',
        filename: 'document.pdf',
        mimeType: 'application/pdf',
        size: 1024000,
      );

      expect(file.id, equals('file1'));
      expect(file.filename, equals('document.pdf'));
      expect(file.mimeType, equals('application/pdf'));
      expect(file.size, equals(1024000));
      expect(file.syncStatus, equals(FileSyncStatus.pending));
    });

    test('should serialize to and from JSON', () {
      final originalFile = FileAttachment(
        id: 'test-file',
        filename: 'test.jpg',
        mimeType: 'image/jpeg',
        size: 512000,
        localPath: '/local/test.jpg',
        remotePath: 'https://example.com/test.jpg',
        syncStatus: FileSyncStatus.synchronized,
        uploadedAt: DateTime.parse('2023-01-01T10:00:00Z'),
        checksum: 'abc123',
      );

      final json = originalFile.toJson();
      final restoredFile = FileAttachment.fromJson(json);

      expect(restoredFile, equals(originalFile));
      expect(restoredFile.id, equals(originalFile.id));
      expect(restoredFile.filename, equals(originalFile.filename));
      expect(restoredFile.mimeType, equals(originalFile.mimeType));
      expect(restoredFile.size, equals(originalFile.size));
      expect(restoredFile.localPath, equals(originalFile.localPath));
      expect(restoredFile.remotePath, equals(originalFile.remotePath));
      expect(restoredFile.syncStatus, equals(originalFile.syncStatus));
      expect(restoredFile.uploadedAt, equals(originalFile.uploadedAt));
      expect(restoredFile.checksum, equals(originalFile.checksum));
    });

    test('should support copyWith for immutable updates', () {
      final originalFile = FileAttachment(
        id: 'file1',
        filename: 'original.jpg',
        mimeType: 'image/jpeg',
        size: 1024,
        syncStatus: FileSyncStatus.pending,
      );

      final updatedFile = originalFile.copyWith(
        syncStatus: FileSyncStatus.synchronized,
        remotePath: 'https://example.com/synced.jpg',
      );

      expect(updatedFile.id, equals(originalFile.id));
      expect(updatedFile.filename, equals(originalFile.filename));
      expect(updatedFile.syncStatus, equals(FileSyncStatus.synchronized));
      expect(updatedFile.remotePath, equals('https://example.com/synced.jpg'));
    });
  });

  group('Fileset Tests', () {
    test('should manage collection of files', () {
      final fileset = Fileset(files: [
        FileAttachment(
          id: '1',
          filename: 'file1.jpg',
          mimeType: 'image/jpeg',
          size: 1024,
        ),
        FileAttachment(
          id: '2',
          filename: 'file2.pdf',
          mimeType: 'application/pdf',
          size: 2048,
          syncStatus: FileSyncStatus.synchronized,
        ),
      ]);

      expect(fileset.count, equals(2));
      expect(fileset.isNotEmpty, isTrue);
      
      final pendingFiles = fileset.pendingFiles;
      expect(pendingFiles.length, equals(1));
      expect(pendingFiles.first.filename, equals('file1.jpg'));
      
      final syncedFiles = fileset.synchronizedFiles;
      expect(syncedFiles.length, equals(1));
      expect(syncedFiles.first.filename, equals('file2.pdf'));
    });

    test('should add and remove files immutably', () {
      final emptyFileset = Fileset.empty;
      
      final newFile = FileAttachment(
        id: 'new-file',
        filename: 'new.jpg',
        mimeType: 'image/jpeg',
        size: 1024,
      );

      final withFile = emptyFileset.addFile(newFile);
      expect(emptyFileset.count, equals(0)); // Original unchanged
      expect(withFile.count, equals(1));
      expect(withFile.findFile('new-file'), isNotNull);

      final withoutFile = withFile.removeFile('new-file');
      expect(withFile.count, equals(1)); // Previous version unchanged
      expect(withoutFile.count, equals(0));
      expect(withoutFile.findFile('new-file'), isNull);
    });

    test('should update file status', () {
      final file = FileAttachment(
        id: 'test-file',
        filename: 'test.jpg',
        mimeType: 'image/jpeg',
        size: 1024,
        syncStatus: FileSyncStatus.pending,
      );

      final fileset = Fileset(files: [file]);
      final updatedFileset = fileset.updateFileStatus('test-file', FileSyncStatus.synchronized);

      expect(fileset.findFile('test-file')!.syncStatus, equals(FileSyncStatus.pending));
      expect(updatedFileset.findFile('test-file')!.syncStatus, equals(FileSyncStatus.synchronized));
    });

    test('should serialize to and from JSON', () {
      final originalFileset = Fileset(files: [
        FileAttachment(
          id: '1',
          filename: 'test1.jpg',
          mimeType: 'image/jpeg',
          size: 1024,
        ),
        FileAttachment(
          id: '2',
          filename: 'test2.pdf',
          mimeType: 'application/pdf',
          size: 2048,
          syncStatus: FileSyncStatus.synchronized,
        ),
      ]);

      final json = originalFileset.toJson();
      final restoredFileset = Fileset.fromJson(json);

      expect(restoredFileset, equals(originalFileset));
      expect(restoredFileset.count, equals(originalFileset.count));
      expect(restoredFileset.files[0].filename, equals('test1.jpg'));
      expect(restoredFileset.files[1].filename, equals('test2.pdf'));
    });
  });

  group('FilesetSyncConfig Tests', () {
    test('should validate file constraints', () {
      final config = FilesetSyncConfig(
        maxFileSize: 1000000, // 1MB
        allowedMimeTypes: ['image/jpeg', 'image/png', 'application/pdf'],
      );

      final validFile = FileAttachment(
        id: '1',
        filename: 'test.jpg',
        mimeType: 'image/jpeg',
        size: 500000,
      );

      final oversizedFile = FileAttachment(
        id: '2',
        filename: 'large.jpg',
        mimeType: 'image/jpeg',
        size: 2000000, // 2MB
      );

      final invalidTypeFile = FileAttachment(
        id: '3',
        filename: 'video.mp4',
        mimeType: 'video/mp4',
        size: 500000,
      );

      expect(config.isFileAllowed(validFile), isTrue);
      expect(config.isFileAllowed(oversizedFile), isFalse);
      expect(config.isFileAllowed(invalidTypeFile), isFalse);
    });

    test('should allow all files when no constraints are set', () {
      const config = FilesetSyncConfig();

      final anyFile = FileAttachment(
        id: '1',
        filename: 'any.file',
        mimeType: 'any/type',
        size: 999999999,
      );

      expect(config.isFileAllowed(anyFile), isTrue);
    });
  });

  group('FileSyncStatus Tests', () {
    test('should have all expected status values', () {
      expect(FileSyncStatus.values.length, equals(5));
      expect(FileSyncStatus.values, contains(FileSyncStatus.pending));
      expect(FileSyncStatus.values, contains(FileSyncStatus.uploading));
      expect(FileSyncStatus.values, contains(FileSyncStatus.synchronized));
      expect(FileSyncStatus.values, contains(FileSyncStatus.failed));
      expect(FileSyncStatus.values, contains(FileSyncStatus.localOnly));
    });
  });
}