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
    
    // First pass: Find schema definitions to understand table structures
    final schemaDefinitions = _findSchemaDefinitions(library);
    
    // Second pass: Look for classes extending DbRecord with @GenerateDbRecord annotation
    for (final element in library.allElements) {
      if (element is ClassElement) {
        final annotation = _getDbRecordAnnotation(element);
        if (annotation != null && _extendsDbRecord(element)) {
          final tableName = _getTableNameFromAnnotation(annotation);
          if (tableName != null) {
            final table = _findTableInSchemas(tableName, schemaDefinitions);
            if (table != null) {
              buffer.writeln(_generateRecordClass(element, table));
              buffer.writeln();
            } else {
              // Generate a warning comment if table not found
              buffer.writeln('// WARNING: Table "$tableName" not found in any schema definition');
              buffer.writeln('// for class ${element.name}');
              buffer.writeln();
            }
          }
        }
      }
    }
    
    return buffer.toString();
  }

  /// Finds schema definitions in the library by looking for SchemaBuilder usage
  List<Schema> _findSchemaDefinitions(LibraryReader library) {
    // This is a simplified approach - in practice, this would need more sophisticated
    // AST analysis to extract schema definitions from code
    // For now, return an empty list
    return [];
  }

  /// Finds a table definition in the collected schemas
  Table? _findTableInSchemas(String tableName, List<Schema> schemas) {
    for (final schema in schemas) {
      final table = schema.userTables.where((t) => t.name == tableName).firstOrNull;
      if (table != null) return table;
    }
    return null;
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
  String _generateRecordClass(ClassElement element, Table table) {
    final className = element.name;
    final buffer = StringBuffer();
    
    // Generate extension methods for the existing class
    buffer.writeln('/// Generated typed properties for $className');
    buffer.writeln('extension ${className}Generated on $className {');
    
    // Generate typed getters for each column (except system columns)
    final userColumns = table.columns.where((col) => !col.name.startsWith('system_')).toList();
    
    for (final column in userColumns) {
      buffer.writeln(_generateGetter(column));
    }
    
    if (userColumns.isNotEmpty) {
      buffer.writeln();
    }
    
    // Generate typed setters for each column (except system columns)
    for (final column in userColumns) {
      buffer.writeln(_generateSetter(column));
    }
    
    buffer.writeln('}');
    
    return buffer.toString();
  }

  /// Generates a typed getter for a column
  String _generateGetter(Column column) {
    final propertyName = _camelCase(column.name);
    final dartType = _getDartType(column);
    final helperMethod = _getHelperMethod(column);
    
    return '  /// Gets the ${column.name} column value.\n'
           '  $dartType get $propertyName => $helperMethod(\'${column.name}\');';
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
