import 'dart:convert';
import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('Fileset Column Type Tests', () {
    late Database database;
    late SchemaMigrator migrator;
    late DataAccess dataAccess;
    late FilesetManager filesetManager;
    late String tempDir;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      database = await openDatabase(':memory:');
      migrator = SchemaMigrator();
      
      // Create a temporary directory for file storage
      tempDir = '/tmp/fileset_test_${DateTime.now().millisecondsSinceEpoch}';
      await Directory(tempDir).create(recursive: true);
      
      // Initialize fileset manager
      filesetManager = FilesetManager(
        database: database,
        storageDirectory: tempDir,
      );
      await filesetManager.initialize();
    });

    tearDown(() async {
      await database.close();
      // Clean up temp directory
      try {
        await Directory(tempDir).delete(recursive: true);
      } catch (e) {
        // Ignore cleanup errors
      }
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

      // Create temporary test files
      final testFile1 = File('${tempDir}/source1.jpg');
      final testFile2 = File('${tempDir}/source2.png');
      await testFile1.writeAsString('fake image data 1');
      await testFile2.writeAsString('fake image data 2');

      // Add files to fileset manager and get their IDs
      final filesetId1 = await filesetManager.addFile(
        originalFilename: 'vacation.jpg',
        sourceFilePath: testFile1.path,
        mimeType: 'image/jpeg',
      );
      
      final filesetId2 = await filesetManager.addFile(
        originalFilename: 'landscape.png',
        sourceFilePath: testFile2.path,
        mimeType: 'image/png',
      );

      // Create a fileset with the file IDs
      final fileset = Fileset(filesetIds: [filesetId1, filesetId2]);

      // Insert album with fileset data
      final albumId = await dataAccess.insert('albums', {
        'title': 'Summer Vacation',
        'photos': fileset.toDatabaseValue(),
      });

      // Retrieve and verify the data
      final retrievedRow = await dataAccess.getByPrimaryKey('albums', albumId);
      expect(retrievedRow, isNotNull);
      expect(retrievedRow!['title'], equals('Summer Vacation'));
      
      final retrievedFileset = Fileset.fromDatabaseValue(retrievedRow['photos'] as String?);
      expect(retrievedFileset.count, equals(2));
      
      // Load actual file data through manager
      final files = await retrievedFileset.loadFiles(filesetManager);
      expect(files.length, equals(2));
      
      // Check that both files are present (order might vary)
      final filenames = files.map((f) => f.filename).toSet();
      expect(filenames.contains('vacation.jpg'), isTrue);
      expect(filenames.contains('landscape.png'), isTrue);
      
      // All files should have pending status initially
      for (final file in files) {
        expect(file.syncStatus, equals(FileSyncStatus.pending));
      }
    });

    test('should handle empty fileset', () async {
      final schema = SchemaBuilder()
          .table('documents', (table) => table
              .autoIncrementPrimaryKey('id')
              .text('title', (col) => col.notNull())
              .fileset('attachments'));

      await migrator.migrate(database, schema);
      dataAccess = await DataAccess.create(database: database, schema: schema);

      // Insert with empty fileset
      final docId = await dataAccess.insert('documents', {
        'title': 'Empty Document',
        'attachments': Fileset.empty.toDatabaseValue(),
      });

      // Retrieve and verify
      final retrievedRow = await dataAccess.getByPrimaryKey('documents', docId);
      final retrievedFileset = Fileset.fromDatabaseValue(retrievedRow!['attachments'] as String?);
      
      expect(retrievedFileset.isEmpty, isTrue);
      expect(retrievedFileset.count, equals(0));
    });

    test('should validate fileset requires encoding', () {
      expect(SqliteDataType.fileset.requiresEncoding, isTrue);
    });
  });

  group('FileAttachment Tests', () {
    test('should create FileAttachment with required properties', () {
      final file = FileAttachment(
        id: 'test-id',
        filename: 'document.pdf',
        mimeType: 'application/pdf',
        size: 1024,
      );

      expect(file.id, equals('test-id'));
      expect(file.filename, equals('document.pdf'));
      expect(file.mimeType, equals('application/pdf'));
      expect(file.size, equals(1024));
      expect(file.syncStatus, equals(FileSyncStatus.pending));
    });

    test('should serialize to and from JSON', () {
      final file = FileAttachment(
        id: 'test-id',
        filename: 'document.pdf',
        mimeType: 'application/pdf',
        size: 1024,
        localPath: '/local/document.pdf',
        syncStatus: FileSyncStatus.synchronized,
        uploadedAt: DateTime.parse('2023-01-01T12:00:00Z'),
      );

      final json = file.toJson();
      final restored = FileAttachment.fromJson(json);

      expect(restored.id, equals(file.id));
      expect(restored.filename, equals(file.filename));
      expect(restored.mimeType, equals(file.mimeType));
      expect(restored.size, equals(file.size));
      expect(restored.localPath, equals(file.localPath));
      expect(restored.syncStatus, equals(file.syncStatus));
      expect(restored.uploadedAt, equals(file.uploadedAt));
    });

    test('should support copyWith for immutable updates', () {
      final original = FileAttachment(
        id: 'test-id',
        filename: 'document.pdf',
        mimeType: 'application/pdf',
        size: 1024,
      );

      final updated = original.copyWith(
        syncStatus: FileSyncStatus.synchronized,
        remotePath: 'https://example.com/document.pdf',
      );

      expect(updated.id, equals(original.id));
      expect(updated.filename, equals(original.filename));
      expect(updated.syncStatus, equals(FileSyncStatus.synchronized));
      expect(updated.remotePath, equals('https://example.com/document.pdf'));
    });
  });

  group('Fileset Tests', () {
    late Database database;
    late FilesetManager filesetManager;
    late String tempDir;

    setUp(() async {
      database = await openDatabase(':memory:');
      tempDir = '/tmp/fileset_test_${DateTime.now().millisecondsSinceEpoch}';
      await Directory(tempDir).create(recursive: true);
      
      filesetManager = FilesetManager(
        database: database,
        storageDirectory: tempDir,
      );
      await filesetManager.initialize();
    });

    tearDown(() async {
      await database.close();
      try {
        await Directory(tempDir).delete(recursive: true);
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    test('should manage collection of file IDs', () async {
      final emptyFileset = Fileset.empty;
      expect(emptyFileset.isEmpty, isTrue);
      expect(emptyFileset.count, equals(0));

      // Add a file ID
      final withFile = emptyFileset.addFilesetId('test-id');
      expect(withFile.count, equals(1));
      expect(withFile.containsFilesetId('test-id'), isTrue);
    });

    test('should add and remove file IDs immutably', () async {
      // Create a test file
      final testFile = File('${tempDir}/test.jpg');
      await testFile.writeAsString('fake image data');

      final filesetId = await filesetManager.addFile(
        originalFilename: 'test.jpg',
        sourceFilePath: testFile.path,
        mimeType: 'image/jpeg',
      );

      final originalFileset = Fileset(filesetIds: [filesetId]);
      
      // Add another ID
      final withNewId = originalFileset.addFilesetId('new-id');
      expect(withNewId.count, equals(2));
      expect(originalFileset.count, equals(1)); // Original unchanged

      // Remove an ID
      final withoutId = withNewId.removeFilesetId('new-id');
      expect(withoutId.count, equals(1));
      expect(withoutId.containsFilesetId(filesetId), isTrue);
      expect(withoutId.containsFilesetId('new-id'), isFalse);
    });

    test('should serialize to and from database value', () {
      final fileset = Fileset(filesetIds: ['id1', 'id2', 'id3']);
      
      final dbValue = fileset.toDatabaseValue();
      final restoredFileset = Fileset.fromDatabaseValue(dbValue);
      
      expect(restoredFileset.count, equals(3));
      expect(restoredFileset.containsFilesetId('id1'), isTrue);
      expect(restoredFileset.containsFilesetId('id2'), isTrue);
      expect(restoredFileset.containsFilesetId('id3'), isTrue);
    });
  });

  group('FilesetSyncConfig Tests', () {
    test('should validate file constraints', () {
      final config = FilesetSyncConfig(
        maxFileSize: 1024,
        allowedMimeTypes: ['image/jpeg', 'image/png'],
      );

      final validFile = FileAttachment(
        id: 'valid',
        filename: 'test.jpg',
        mimeType: 'image/jpeg',
        size: 512,
      );

      final tooLargeFile = FileAttachment(
        id: 'large',
        filename: 'large.jpg',
        mimeType: 'image/jpeg',
        size: 2048,
      );

      final wrongTypeFile = FileAttachment(
        id: 'wrong',
        filename: 'document.pdf',
        mimeType: 'application/pdf',
        size: 512,
      );

      expect(config.isFileAllowed(validFile), isTrue);
      expect(config.isFileAllowed(tooLargeFile), isFalse);
      expect(config.isFileAllowed(wrongTypeFile), isFalse);
    });

    test('should allow all files when no constraints are set', () {
      final config = FilesetSyncConfig();

      final file = FileAttachment(
        id: 'test',
        filename: 'any.file',
        mimeType: 'any/type',
        size: 999999999,
      );

      expect(config.isFileAllowed(file), isTrue);
    });
  });

  group('FileSyncStatus Tests', () {
    test('should have all expected status values', () {
      expect(FileSyncStatus.values.length, equals(5));
      expect(FileSyncStatus.values.contains(FileSyncStatus.pending), isTrue);
      expect(FileSyncStatus.values.contains(FileSyncStatus.uploading), isTrue);
      expect(FileSyncStatus.values.contains(FileSyncStatus.synchronized), isTrue);
      expect(FileSyncStatus.values.contains(FileSyncStatus.failed), isTrue);
      expect(FileSyncStatus.values.contains(FileSyncStatus.localOnly), isTrue);
    });
  });
}