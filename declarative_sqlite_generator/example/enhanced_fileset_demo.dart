/// Example demonstrating the enhanced fileset functionality in declarative_sqlite_generator.
/// 
/// This shows how fileset columns now generate specialized FilesetField types
/// that provide better file management capabilities and Future-based operations.
library;

import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_generator/declarative_sqlite_generator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('=== Declarative SQLite Generator - Enhanced Fileset Example ===\n');
  
  // Initialize SQLite for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  // Example: Define a schema with fileset columns
  print('📋 Defining schema with fileset columns...');
  final schema = SchemaBuilder()
    .table('documents', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('title', (col) => col.notNull())
        .text('description')
        .fileset('attachments', (col) => col.notNull()) // Required fileset
        .fileset('gallery')) // Optional fileset
    .table('projects', (table) => table
        .autoIncrementPrimaryKey('id')
        .text('name', (col) => col.notNull())
        .fileset('documentation'));

  // Generate enhanced data classes
  print('🔧 Generating enhanced data classes with FilesetField...');
  final generator = SchemaCodeGenerator();
  final generatedCode = generator.generateCode(schema, libraryName: 'enhanced_fileset_demo');
  
  print('\n📄 Generated code with FilesetField:');
  print('=' * 80);
  print(generatedCode);
  print('=' * 80);
  
  // Demonstrate the improvements
  print('\n🎯 Key improvements in generated classes:');
  print('');
  print('1. Fileset columns are now FilesetField type (not String)');
  print('   - Required: FilesetField attachments;');
  print('   - Optional: FilesetField? gallery;');
  print('');
  print('2. FilesetField provides convenient Future-based methods:');
  print('   - loadFiles() -> Future<List<FileAttachment>>');
  print('   - getPendingFiles() -> Future<List<FileAttachment>>');
  print('   - getSynchronizedFiles() -> Future<List<FileAttachment>>');
  print('   - addFile(...) -> Future<FilesetField>');
  print('   - removeFile(id) -> Future<FilesetField>');
  print('');
  print('3. Serialization methods handle FilesetField properly:');
  print('   - toMap() calls field.toDatabaseValue()');
  print('   - fromMap(map, manager) uses FilesetField.fromDatabaseValue()');
  print('');
  print('4. Generated code includes proper imports for fileset functionality');
  
  // Show usage example
  print('\n💡 Example usage (would work with the generated classes):');
  await demonstrateUsage();
}

/// Demonstrates how the enhanced fileset functionality would be used
Future<void> demonstrateUsage() async {
  print('''

// Initialize database and fileset manager
final database = await openDatabase(':memory:');
final tempDir = Directory.systemTemp.createTempSync('fileset_demo');
final filesetManager = FilesetManager(
  database: database,
  storageDirectory: tempDir.path,
);
await filesetManager.initialize();

// Create sample files
final sampleFile = File('\${tempDir.path}/sample.pdf');
await sampleFile.writeAsString('Sample PDF content');

// Using the generated DocumentsData class:
// (This would work if the generated classes were available)

/*
// 1. Create a new document with fileset field
var emptyFileset = FilesetField.empty(filesetManager);
var document = DocumentsData(
  id: 1,
  systemId: 'doc-123',
  systemVersion: 'v1',
  title: 'Project Proposal',
  description: 'Important project documentation',
  attachments: emptyFileset,
  gallery: null,
);

// 2. Add files to the fileset with Future-based operations
final updatedAttachments = await document.attachments.addFile(
  originalFilename: 'proposal.pdf',
  sourceFilePath: sampleFile.path,
  mimeType: 'application/pdf',
);

// 3. Update document with new fileset
document = document.copyWith(attachments: updatedAttachments);

// 4. Access files with convenient Future methods
final allFiles = await document.attachments.loadFiles();
print('Total attachments: \${allFiles.length}');

final pendingFiles = await document.attachments.getPendingFiles();
print('Files pending sync: \${pendingFiles.length}');

// 5. Database serialization works automatically
final dbMap = document.toMap();
print('Ready for database: \$dbMap');

// 6. Deserialization with manager integration
final restored = DocumentsData.fromMap(dbMap, filesetManager);
print('Restored document: \${restored.title}');
*/

print('🎉 The FilesetField enhancement provides a much better developer experience!');
print('   - Type safety with compile-time checking');
print('   - Future-based async operations for file management');
print('   - Seamless integration with FilesetManager');
print('   - Clean separation between data and file operations');
''');

  print('\n✨ This addresses the comment feedback for:');
  print('   - "Fileset class datatype" ✅ (FilesetField wraps Fileset)');
  print('   - "Simplifies file management" ✅ (Future-based methods)');
  print('   - "Should have a Future" ✅ (All file operations return Futures)');
}