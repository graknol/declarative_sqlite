import 'dart:convert';
import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:test_generator/schema.dart' as schema_def;

void main() async {
  try {
    print('Starting schema generation...');
    final builder = SchemaBuilder();
    print('Created SchemaBuilder');
    
    print('Calling schema function: defineSchema');
    schema_def.defineSchema(builder);
    print('Schema function completed');
    
    print('Building schema...');
    final schema = builder.build();
    print('Schema built with ${schema.tables.length} tables');
    
    print('Converting to JSON...');
    final jsonString = jsonEncode(schema.toJson());
    print('JSON created, length: ${jsonString.length}');
    
    print('Writing to file: schema_output.json');
    await File('schema_output.json').writeAsString(jsonString);
    print('Schema generation completed successfully');
  } catch (e, stackTrace) {
    print('Error during schema generation: $e');
    print('Stack trace: $stackTrace');
    exit(1);
  }
}