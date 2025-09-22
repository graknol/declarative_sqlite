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
    
    // Look for schema definitions in the library
    for (final element in library.allElements) {
      if (element is VariableElement) {
        // Check if this is a Schema variable
        final annotation = _getSchemaAnnotation(element);
        if (annotation != null) {
          final schema = _parseSchema(element);
          if (schema != null) {
            buffer.writeln(_generateRecordClasses(schema));
          }
        }
      }
    }
    
    return buffer.toString();
  }

  /// Checks if the element has a @GenerateRecords annotation
  Object? _getSchemaAnnotation(VariableElement element) {
    for (final metadata in element.metadata) {
      final annotation = metadata.computeConstantValue();
      if (annotation?.type?.element?.name == 'GenerateRecords') {
        return annotation;
      }
    }
    return null;
  }

  /// Attempts to parse a Schema from the variable element
  /// This is a simplified version - in practice, you'd need more sophisticated
  /// analysis of the schema definition
  Schema? _parseSchema(VariableElement element) {
    // TODO: Implement schema parsing from the AST
    // For now, return null as this requires complex AST analysis
    return null;
  }

  /// Generates typed record classes for all tables in the schema
  String _generateRecordClasses(Schema schema) {
    final buffer = StringBuffer();
    
    for (final table in schema.userTables) {
      buffer.writeln(_generateRecordClass(table));
      buffer.writeln();
    }
    
    return buffer.toString();
  }

  /// Generates a typed record class for a single table
  String _generateRecordClass(Table table) {
    final className = _pascalCase(table.name);
    final buffer = StringBuffer();
    
    buffer.writeln('/// Generated record class for the ${table.name} table.');
    buffer.writeln('class $className extends DbRecord {');
    buffer.writeln('  $className(Map<String, Object?> data, DeclarativeDatabase database)');
    buffer.writeln('      : super(data, \'${table.name}\', database);');
    buffer.writeln();
    
    // Generate typed getters for each column
    for (final column in table.columns) {
      buffer.writeln(_generateGetter(column));
    }
    
    buffer.writeln();
    
    // Generate typed setters for each column
    for (final column in table.columns) {
      buffer.writeln(_generateSetter(column));
    }
    
    buffer.writeln();
    
    // Generate factory method
    buffer.writeln('  /// Creates a $className from a Map.');
    buffer.writeln('  static $className fromMap(Map<String, Object?> data, DeclarativeDatabase database) {');
    buffer.writeln('    return $className(data, database);');
    buffer.writeln('  }');
    
    buffer.writeln('}');
    
    return buffer.toString();
  }

  /// Generates a typed getter for a column
  String _generateGetter(Column column) {
    final propertyName = _camelCase(column.name);
    final dartType = _getDartType(column);
    final helperMethod = _getHelperMethod(column);
    
    return '  /// Gets the ${column.name} column value.\n'
           '  $dartType get $propertyName => $helperMethod(\'${column.name}\')${column.isNotNull ? '!' : ''};';
  }

  /// Generates a typed setter for a column
  String _generateSetter(Column column) {
    final propertyName = _camelCase(column.name);
    final dartType = _getDartType(column);
    final helperMethod = _getSetterHelperMethod(column);
    
    return '  /// Sets the ${column.name} column value.\n'
           '  set $propertyName($dartType value) => $helperMethod(\'${column.name}\', value);';
  }

  /// Gets the Dart type for a column
  String _getDartType(Column column) {
    final baseType = switch (column.logicalType) {
      'text' || 'guid' => 'String',
      'integer' => 'int',
      'real' => 'double',
      'date' => 'DateTime',
      'fileset' => 'FilesetField',
      _ => 'Object',
    };
    
    return column.isNotNull ? baseType : '$baseType?';
  }

  /// Gets the helper method name for getting values
  String _getHelperMethod(Column column) {
    return switch (column.logicalType) {
      'text' || 'guid' => column.isNotNull ? 'getTextNotNull' : 'getText',
      'integer' => column.isNotNull ? 'getIntegerNotNull' : 'getInteger',
      'real' => column.isNotNull ? 'getRealNotNull' : 'getReal',
      'date' => column.isNotNull ? 'getDateTimeNotNull' : 'getDateTime',
      'fileset' => column.isNotNull ? 'getFilesetFieldNotNull' : 'getFilesetField',
      _ => 'getValue',
    };
  }

  /// Gets the helper method name for setting values
  String _getSetterHelperMethod(Column column) {
    return switch (column.logicalType) {
      'text' || 'guid' => 'setText',
      'integer' => 'setInteger',
      'real' => 'setReal',
      'date' => 'setDateTime',
      'fileset' => 'setFilesetField',
      _ => 'setValue',
    };
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

/// Annotation to mark a Schema for record generation
class GenerateRecords {
  const GenerateRecords();
}
