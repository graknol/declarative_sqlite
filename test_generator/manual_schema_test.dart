import 'dart:convert';
import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'lib/schema.dart' as schema_def;

void main() async {
  print('Starting schema generation...');
  
  try {
    print('Creating SchemaBuilder...');
    final builder = SchemaBuilder();
    
    print('Calling defineSchema...');
    schema_def.defineSchema(builder);
    
    print('Building schema...');
    final schema = builder.build();
    
    print('Converting to JSON...');
    final jsonString = jsonEncode(schema.toJson());
    
    print('Schema JSON generated:');
    print(jsonString);
    
    // Write to file
    final file = File('schema_output.json');
    await file.writeAsString(jsonString);
    print('Schema written to schema_output.json');
    
  } catch (e, st) {
    print('Error during schema generation: $e');
    print('Stack trace: $st');
  }
}