import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:declarative_sqlite/src/sync/sqlite_dirty_row_store.dart';

import 'in_memory_file_repository.dart';

void main() {
  group('FilesetField Integration', () {
    late DeclarativeDatabase db;
    late InMemoryFileRepository fileRepo;

    setUp(() async {
      // Initialize FFI for testing
      sqfliteFfiInit();
      
      fileRepo = InMemoryFileRepository();
      
      // Create a schema with a table containing fileset columns
      final schema = SchemaBuilder()
        .table('documents', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title', (col) => col.notNull())
          .fileset('attachments', (col) => col.notNull()) // Required fileset
          .fileset('gallery')) // Optional fileset
        .build();

      db = await DeclarativeDatabase.open(
        ':memory:',
        databaseFactory: databaseFactoryFfi,
        schema: schema,
        dirtyRowStore: SqliteDirtyRowStore(),
        fileRepository: fileRepo,
      );
    });

    test('End-to-end fileset column mapping workflow', () async {
      // 1. Insert a document with fileset data
      await db.insert('documents', {
        'title': 'Test Document',
        'attachments': 'doc-attachments-123',
        'gallery': 'doc-gallery-456',
      });

      // 2. Query the document
      final rows = await db.queryTable('documents');
      expect(rows.length, equals(1));
      final row = rows.first;
      
      // 3. Create FilesetField instances from database values
      final attachments = DataMappingUtils.filesetFieldFromValue(
        row['attachments'],
        db,
      );
      final gallery = DataMappingUtils.filesetFieldFromValue(
        row['gallery'],
        db,
      );
      
      expect(attachments, isNotNull);
      expect(attachments!.filesetId, equals('doc-attachments-123'));
      expect(attachments.hasValue, isTrue);
      
      expect(gallery, isNotNull);
      expect(gallery!.filesetId, equals('doc-gallery-456'));
      expect(gallery.hasValue, isTrue);
      
      // 4. Use the FilesetField to manage files
      final pdfContent = Uint8List.fromList([80, 68, 70, 45, 49]); // PDF header-like
      final imageContent = Uint8List.fromList([255, 216, 255, 224]); // JPEG header-like
      
      // Add files to attachments
      final pdfId = await attachments.addFile('document.pdf', pdfContent);
      final docId = await attachments.addFile('notes.txt', Uint8List.fromList('Test notes'.codeUnits));
      
      // Add files to gallery
      final imageId = await gallery.addFile('photo.jpg', imageContent);
      
      // 5. Verify files were added correctly
      expect(await attachments.getFileCount(), equals(2));
      expect(await gallery.getFileCount(), equals(1));
      
      final attachmentFiles = await attachments.getFiles();
      expect(attachmentFiles.length, equals(2));
      expect(attachmentFiles.any((f) => f['name'] == 'document.pdf'), isTrue);
      expect(attachmentFiles.any((f) => f['name'] == 'notes.txt'), isTrue);
      
      final galleryFiles = await gallery.getFiles();
      expect(galleryFiles.length, equals(1));
      expect(galleryFiles.first['name'], equals('photo.jpg'));
      
      // 6. Retrieve and verify file content
      final retrievedPdf = await attachments.getFileContent(pdfId);
      expect(retrievedPdf, equals(pdfContent));
      
      final retrievedImage = await gallery.getFileContent(imageId);
      expect(retrievedImage, equals(imageContent));
      
      // 7. Delete a file
      await attachments.deleteFile(docId);
      expect(await attachments.getFileCount(), equals(1));
      
      // 8. Verify the deleted file is gone
      final remainingFiles = await attachments.getFiles();
      expect(remainingFiles.length, equals(1));
      expect(remainingFiles.first['name'], equals('document.pdf'));
    });

    test('FilesetField works with null values from database', () async {
      // Insert a document with null gallery
      await db.insert('documents', {
        'title': 'Document with null gallery',
        'attachments': 'doc-attachments-789',
        'gallery': null, // Null fileset
      });

      final rows = await db.queryTable('documents');
      final row = rows.first;
      
      final attachments = DataMappingUtils.filesetFieldFromValue(
        row['attachments'],
        db,
      );
      final gallery = DataMappingUtils.filesetFieldFromValue(
        row['gallery'],
        db,
      );
      
      expect(attachments, isNotNull);
      expect(attachments!.hasValue, isTrue);
      
      expect(gallery, isNull); // Should be null for null database value
    });

    test('Converting FilesetField back to database values works', () async {
      // Create FilesetField instances
      final attachments = FilesetField.fromDatabaseValue('test-attachments', db);
      final gallery = FilesetField.fromDatabaseValue('test-gallery', db);
      
      // Convert back to database values
      final attachmentsValue = DataMappingUtils.filesetFieldToValue(attachments);
      final galleryValue = DataMappingUtils.filesetFieldToValue(gallery);
      final nullValue = DataMappingUtils.filesetFieldToValue(null);
      
      expect(attachmentsValue, equals('test-attachments'));
      expect(galleryValue, equals('test-gallery'));
      expect(nullValue, isNull);
      
      // Use these values to insert into database
      await db.insert('documents', {
        'title': 'Test Round Trip',
        'attachments': attachmentsValue,
        'gallery': galleryValue,
      });
      
      // Query back and verify
      final rows = await db.queryTable('documents', where: 'title = ?', whereArgs: ['Test Round Trip']);
      expect(rows.length, equals(1));
      expect(rows.first['attachments'], equals('test-attachments'));
      expect(rows.first['gallery'], equals('test-gallery'));
    });

    test('FilesetField handles empty string filesets', () async {
      // Insert with empty string fileset
      await db.insert('documents', {
        'title': 'Empty fileset test',
        'attachments': '',
        'gallery': null,
      });

      final rows = await db.queryTable('documents');
      final row = rows.first;
      
      final attachments = DataMappingUtils.filesetFieldFromValue(
        row['attachments'],
        db,
      );
      
      expect(attachments, isNotNull);
      expect(attachments!.filesetId, equals(''));
      expect(attachments.hasValue, isFalse); // Empty string should be considered no value
      
      // Should not be able to add files to empty fileset
      expect(
        () async => await attachments.addFile('test.txt', Uint8List.fromList([1, 2, 3])),
        throwsA(isA<StateError>()),
      );
      
      // Should return empty results for queries
      expect(await attachments.getFiles(), isEmpty);
      expect(await attachments.getFileCount(), equals(0));
    });
  });
}