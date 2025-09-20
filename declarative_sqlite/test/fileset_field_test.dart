import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite/src/files/fileset_field.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:declarative_sqlite/src/sync/sqlite_dirty_row_store.dart';

import 'in_memory_file_repository.dart';

void main() {
  group('FilesetField', () {
    late DeclarativeDatabase db;
    late InMemoryFileRepository fileRepo;

    setUp(() async {
      // Initialize FFI for testing
      sqfliteFfiInit();
      
      fileRepo = InMemoryFileRepository();
      
      // Create a simple schema with a fileset column
      final schema = SchemaBuilder()
        .table('documents', (table) => table
          .autoIncrementPrimaryKey('id')
          .text('title')
          .fileset('attachments'))
        .build();

      db = await DeclarativeDatabase.open(
        ':memory:',
        databaseFactory: databaseFactoryFfi,
        schema: schema,
        dirtyRowStore: SqliteDirtyRowStore(),
        fileRepository: fileRepo,
      );
    });

    test('FilesetField can be created from database value', () {
      final field = FilesetField.fromDatabaseValue('test-fileset-id', db);
      
      expect(field.filesetId, equals('test-fileset-id'));
      expect(field.hasValue, isTrue);
    });

    test('FilesetField handles null values', () {
      final field = FilesetField.fromDatabaseValue(null, db);
      
      expect(field.filesetId, isNull);
      expect(field.hasValue, isFalse);
    });

    test('FilesetField handles empty string values', () {
      final field = FilesetField.fromDatabaseValue('', db);
      
      expect(field.filesetId, equals(''));
      expect(field.hasValue, isFalse);
    });

    test('FilesetField can add and retrieve files', () async {
      final field = FilesetField.fromDatabaseValue('test-fileset', db);
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      
      // Add a file
      final fileId = await field.addFile('test.txt', content);
      expect(fileId, isNotNull);
      expect(fileId, isNotEmpty);
      
      // Retrieve the file content
      final retrievedContent = await field.getFileContent(fileId);
      expect(retrievedContent, equals(content));
      
      // Check file count
      final count = await field.getFileCount();
      expect(count, equals(1));
      
      // Get all files
      final files = await field.getFiles();
      expect(files.length, equals(1));
      expect(files.first['name'], equals('test.txt'));
      expect(files.first['size'], equals(5));
    });

    test('FilesetField throws when adding to null fileset', () async {
      final field = FilesetField.fromDatabaseValue(null, db);
      final content = Uint8List.fromList([1, 2, 3]);
      
      expect(
        () async => await field.addFile('test.txt', content),
        throwsA(isA<StateError>()),
      );
    });

    test('FilesetField can delete files', () async {
      final field = FilesetField.fromDatabaseValue('test-fileset', db);
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      
      // Add a file
      final fileId = await field.addFile('test.txt', content);
      
      // Verify it exists
      expect(await field.getFileCount(), equals(1));
      
      // Delete the file
      await field.deleteFile(fileId);
      
      // Verify it's gone
      expect(await field.getFileCount(), equals(0));
      expect(await field.getFileContent(fileId), isNull);
    });

    test('FilesetField returns empty list for null fileset getFiles', () async {
      final field = FilesetField.fromDatabaseValue(null, db);
      
      final files = await field.getFiles();
      expect(files, isEmpty);
    });

    test('FilesetField returns 0 count for null fileset', () async {
      final field = FilesetField.fromDatabaseValue(null, db);
      
      final count = await field.getFileCount();
      expect(count, equals(0));
    });

    test('FilesetField toDatabaseValue returns correct value', () {
      final field1 = FilesetField.fromDatabaseValue('test-id', db);
      expect(field1.toDatabaseValue(), equals('test-id'));
      
      final field2 = FilesetField.fromDatabaseValue(null, db);
      expect(field2.toDatabaseValue(), isNull);
    });

    test('FilesetField equality and hashCode work correctly', () {
      final field1 = FilesetField.fromDatabaseValue('test-id', db);
      final field2 = FilesetField.fromDatabaseValue('test-id', db);
      final field3 = FilesetField.fromDatabaseValue('other-id', db);
      
      expect(field1, equals(field2));
      expect(field1.hashCode, equals(field2.hashCode));
      expect(field1, isNot(equals(field3)));
    });

    test('FilesetField toString provides useful information', () {
      final field1 = FilesetField.fromDatabaseValue('test-id', db);
      expect(field1.toString(), contains('test-id'));
      expect(field1.toString(), contains('true'));
      
      final field2 = FilesetField.fromDatabaseValue(null, db);
      expect(field2.toString(), contains('null'));
      expect(field2.toString(), contains('false'));
    });
  });

  group('DataMappingUtils', () {
    late DeclarativeDatabase db;

    setUp(() async {
      sqfliteFfiInit();
      
      final fileRepo = InMemoryFileRepository();
      final schema = SchemaBuilder().build();

      db = await DeclarativeDatabase.open(
        ':memory:',
        databaseFactory: databaseFactoryFfi,
        schema: schema,
        dirtyRowStore: SqliteDirtyRowStore(),
        fileRepository: fileRepo,
      );
    });

    test('filesetFieldFromValue creates correct FilesetField', () {
      final field = DataMappingUtils.filesetFieldFromValue('test-id', db);
      
      expect(field, isNotNull);
      expect(field!.filesetId, equals('test-id'));
      expect(field.hasValue, isTrue);
    });

    test('filesetFieldFromValue handles null values', () {
      final field = DataMappingUtils.filesetFieldFromValue(null, db);
      
      expect(field, isNull);
    });

    test('filesetFieldToValue converts back correctly', () {
      final field = FilesetField.fromDatabaseValue('test-id', db);
      final value = DataMappingUtils.filesetFieldToValue(field);
      
      expect(value, equals('test-id'));
    });

    test('filesetFieldToValue handles null field', () {
      final value = DataMappingUtils.filesetFieldToValue(null);
      
      expect(value, isNull);
    });
  });
}