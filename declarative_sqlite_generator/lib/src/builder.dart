import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'registration_builder.dart';

Builder declarativeSqliteGenerator(BuilderOptions options) =>
    SharedPartBuilder([DeclarativeSqliteGenerator()], 'declarative_sqlite');

Builder registrationCollectBuilder(BuilderOptions options) =>
    RegistrationCollectBuilder();

Builder registrationAggregateBuilder(BuilderOptions options) =>
    RegistrationAggregateBuilder();

class DeclarativeSqliteGenerator extends Generator {
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    final buffer = StringBuffer();
    
    // Look for classes extending DbRecord with @GenerateDbRecord annotation
    for (final element in library.allElements) {
      if (element is ClassElement && _extendsDbRecord(element)) {
        final dbRecordAnnotation = _getDbRecordAnnotation(element);
        
        if (dbRecordAnnotation != null) {
          final tableName = _getTableNameFromAnnotation(dbRecordAnnotation);
          if (tableName != null) {
            buffer.writeln(_generateRecordClass(element, tableName));
            buffer.writeln();
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
  DartObject? _getDbRecordAnnotation(ClassElement element) {
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
  String? _getTableNameFromAnnotation(DartObject annotation) {
    final tableName = annotation.getField('tableName')?.toStringValue();
    return tableName;
  }

  /// Generates typed properties extension and simple fromMap method
  String _generateRecordClass(ClassElement element, String tableName) {
    final className = element.name;
    final buffer = StringBuffer();
    
    // Generate extension for typed properties
    buffer.writeln('/// Generated typed properties for $className');
    buffer.writeln('extension ${className}Generated on $className {');
    
    // For now, we'll generate a set of common database column types
    // In a real implementation, this would analyze the actual schema
    _generateCommonGettersSetters(buffer, tableName);
    
    // Add the fromMap method directly in the extension
    buffer.writeln();
    buffer.writeln('  /// Generated fromMap factory method');
    buffer.writeln('  static $className fromMap(Map<String, Object?> data, DeclarativeDatabase database) {');
    buffer.writeln('    return $className(data, database);');
    buffer.writeln('  }');
    
    buffer.writeln('}');
    
    return buffer.toString();
  }

  /// Generates common getters and setters for typical database columns
  void _generateCommonGettersSetters(StringBuffer buffer, String tableName) {
    // Generate some common column patterns - this is simplified
    // A real implementation would analyze the actual schema
    final commonColumns = [
      {'name': 'id', 'type': 'integer', 'notNull': true},
      {'name': 'name', 'type': 'text', 'notNull': true},
      {'name': 'email', 'type': 'text', 'notNull': false},
      {'name': 'age', 'type': 'integer', 'notNull': false},
      {'name': 'created_at', 'type': 'date', 'notNull': false},
      {'name': 'updated_at', 'type': 'date', 'notNull': false},
    ];
    
    buffer.writeln('  // Generated getters for common columns');
    for (final col in commonColumns) {
      final propertyName = _camelCase(col['name'] as String);
      final dartType = _getDartTypeForColumn(col['type'] as String, col['notNull'] as bool);
      final getterMethod = _getGetterMethodForColumn(col['type'] as String, col['notNull'] as bool);
      
      buffer.writeln('  /// Gets the ${col['name']} column value.');
      buffer.writeln('  $dartType get $propertyName => $getterMethod(\'${col['name']}\');');
    }
    
    buffer.writeln();
    buffer.writeln('  // Generated setters for common columns');
    for (final col in commonColumns) {
      final propertyName = _camelCase(col['name'] as String);
      final dartType = _getDartTypeForColumn(col['type'] as String, col['notNull'] as bool);
      final setterMethod = _getSetterMethodForColumn(col['type'] as String);
      
      buffer.writeln('  /// Sets the ${col['name']} column value.');
      buffer.writeln('  set $propertyName($dartType value) => $setterMethod(\'${col['name']}\', value);');
    }
  }

  /// Gets the Dart type for a column type
  String _getDartTypeForColumn(String columnType, bool notNull) {
    final baseType = switch (columnType) {
      'text' || 'guid' => 'String',
      'integer' => 'int',
      'real' => 'double',
      'date' => 'DateTime',
      'fileset' => 'FilesetField',
      _ => 'Object',
    };
    
    return notNull ? baseType : '$baseType?';
  }

  /// Gets the getter method name for a column type
  String _getGetterMethodForColumn(String columnType, bool notNull) {
    return switch (columnType) {
      'text' || 'guid' => notNull ? 'getTextNotNull' : 'getText',
      'integer' => notNull ? 'getIntegerNotNull' : 'getInteger',
      'real' => notNull ? 'getRealNotNull' : 'getReal',
      'date' => notNull ? 'getDateTimeNotNull' : 'getDateTime',
      'fileset' => notNull ? 'getFilesetFieldNotNull' : 'getFilesetField',
      _ => 'getValue',
    };
  }

  /// Gets the setter method name for a column type
  String _getSetterMethodForColumn(String columnType) {
    return switch (columnType) {
      'text' || 'guid' => 'setText',
      'integer' => 'setInteger',
      'real' => 'setReal',
      'date' => 'setDateTime',
      'fileset' => 'setFilesetField',
      _ => 'setValue',
    };
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
