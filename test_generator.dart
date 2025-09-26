import 'dart:io';
import 'dart:convert';
import 'dart:io' show Platform;

/// Standalone test script to debug the temporary script execution issue
Future<void> main() async {
  print('Testing temporary script execution...');
  
  // Create temporary directory and files
  final tempDir = await Directory.systemTemp.createTemp('declarative_sqlite_generator');
  final tempFile = File('${tempDir.path}${Platform.pathSeparator}schema_generator.dart');
  
  print('Temp directory: ${tempDir.path}');
  
  // Create temporary script
  final scriptContent = '''
import 'dart:io';
import 'dart:convert';

void main() {
  print("Script is running...");
  
  // Simple schema for testing
  final schema = {
    'tables': [
      {
        'name': 'test_table',
        'columns': [
          {'name': 'id', 'type': 'INTEGER', 'isPrimaryKey': true},
          {'name': 'name', 'type': 'TEXT'}
        ]
      }
    ]
  };
  
  print("Creating JSON file...");
  
  // Write to working directory
  final file = File('schema.json');
  file.writeAsStringSync(json.encode(schema));
  
  print("JSON file written to: \${file.absolute.path}");
  print("JSON content length: \${json.encode(schema).length}");
}
''';

  // Write script
  await tempFile.writeAsString(scriptContent);
  print('Script written to: ${tempFile.path}');

  try {
    // Execute with working directory set to temp directory
    final result = await Process.run(
      'dart',
      [tempFile.path],
      workingDirectory: tempDir.path,
    );

    print('Exit code: ${result.exitCode}');
    print('stdout: ${result.stdout}');
    print('stderr: ${result.stderr}');

    // Check what files exist in temp directory
    final files = await tempDir.list().toList();
    print('Files in temp directory:');
    for (final file in files) {
      final parts = file.path.split(Platform.pathSeparator);
      print('  ${parts.last}');
    }

    // Check for JSON file specifically
    final jsonFile = File('${tempDir.path}${Platform.pathSeparator}schema.json');
    if (await jsonFile.exists()) {
      final content = await jsonFile.readAsString();
      print('JSON file exists with content: ${content.substring(0, 100)}...');
    } else {
      print('JSON file does not exist');
    }

  } catch (e) {
    print('Error: $e');
  } finally {
    // Cleanup
    await tempDir.delete(recursive: true);
  }
}