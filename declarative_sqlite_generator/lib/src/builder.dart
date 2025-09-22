import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

Builder declarativeSqliteGenerator(BuilderOptions options) =>
    SharedPartBuilder([DeclarativeSqliteGenerator()], 'declarative_sqlite');

class DeclarativeSqliteGenerator extends Generator {
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    final buffer = StringBuffer();
    
    // Look for classes extending DbRecord with @GenerateDbRecord annotation
    for (final element in library.allElements) {
      if (element is ClassElement) {
        final annotation = _getDbRecordAnnotation(element);
        if (annotation != null && _extendsDbRecord(element)) {
          final tableName = _getTableNameFromAnnotation(annotation);
          if (tableName != null) {
            buffer.writeln(_generateRecordClass(element, tableName));
            buffer.writeln();
          }
        }
      }
    }
    
    return buffer.toString();
  }

  /// Checks if the class has a @GenerateDbRecord annotation
  Object? _getDbRecordAnnotation(ClassElement element) {
    for (final metadata in element.metadata) {
      final annotation = metadata.computeConstantValue();
      if (annotation?.type?.element?.name == 'GenerateDbRecord') {
        return annotation;
      }
    }
    return null;
  }

  /// Checks if the class extends DbRecord
  bool _extendsDbRecord(ClassElement element) {
    ClassElement? current = element;
    while (current != null) {
      if (current.supertype?.element?.name == 'DbRecord') {
        return true;
      }
      current = current.supertype?.element;
    }
    return false;
  }

  /// Extracts the table name from the @GenerateDbRecord annotation
  String? _getTableNameFromAnnotation(Object annotation) {
    final constantValue = annotation as dynamic;
    final tableName = constantValue.getField('tableName')?.toStringValue();
    return tableName;
  }

  /// Generates a typed record class for a class element
  String _generateRecordClass(ClassElement element, String tableName) {
    final className = element.name;
    final buffer = StringBuffer();
    
    // TODO: We need to get the table schema to generate the proper getters/setters
    // For now, we'll generate a placeholder comment
    buffer.writeln('// Generated code for $className table: $tableName');
    buffer.writeln('// Table schema needs to be resolved to generate typed getters/setters');
  /// Generates a typed record class for a class element
  String _generateRecordClass(ClassElement element, String tableName) {
    final className = element.name;
    final buffer = StringBuffer();
    
    // Generate extension methods for the existing class
    buffer.writeln('/// Generated typed properties for $className');
    buffer.writeln('extension ${className}Generated on $className {');
    buffer.writeln('  // TODO: Generate getters and setters based on table schema');
    buffer.writeln('  // Table: $tableName');
    buffer.writeln('  // Schema resolution needed to generate proper typed methods');
    buffer.writeln('}');
    
    return buffer.toString();
  }

  /// Converts snake_case to PascalCase
  String _pascalCase(String input) {
    return input.split('_')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join('');
  }

  /// Converts snake_case to camelCase
  String _camelCase(String input) {
    final parts = input.split('_');
    if (parts.isEmpty) return input;
    
    final result = parts[0].toLowerCase() +
        parts.skip(1)
            .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase())
            .join('');
    
    return result;
  }
}
