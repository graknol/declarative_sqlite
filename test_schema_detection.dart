import 'dart:io';
import 'dart:convert';

/// Test the updated generator schema detection logic
Future<void> main() async {
  print('Testing schema function detection...');
  
  // Simulate the content of main.dart
  final schemaContent = '''
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';

class DeclarativeSqliteDemo extends StatelessWidget {
  const DeclarativeSqliteDemo({super.key});

  void _buildDatabaseSchema(SchemaBuilder builder) {
    // Users table
    builder.table('users', (table) {
      table.guid('id').notNull('');
      table.text('name').notNull('');
    });
  }
}
''';

  // Test regex patterns
  print('\n=== Testing Function Pattern ===');
  final functionNamePattern = RegExp(r'(?:void\s+)?(\w*[Ss]chema\w*)\s*\(\s*SchemaBuilder\s+\w+\s*\)');
  final match = functionNamePattern.firstMatch(schemaContent);
  
  if (match != null) {
    final functionName = match.group(1)!;
    print('Found schema function: $functionName');
    
    // Check if the function is inside a class (more flexible pattern)
    final classPattern = RegExp(r'class\s+(\w+)[^{]*\{[\s\S]*?' + functionName, multiLine: true, dotAll: true);
    final classMatch = classPattern.firstMatch(schemaContent);
    if (classMatch != null) {
      final className = classMatch.group(1)!;
      print('Schema function is in class: $className');
      print('Result: Function "$functionName" found in class "$className"');
    } else {
      print('Function is standalone (not in a class)');
    }
  } else {
    print('No schema function found');
  }

  print('\n=== Test Completed ===');
}