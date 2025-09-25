import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:logging/logging.dart';
import 'package:source_gen/source_gen.dart';

/// Generates `.db.dart` part files for classes annotated with `@GenerateDbRecord`.
class DeclarativeSqliteGenerator extends GeneratorForAnnotation<GenerateDbRecord> {
  static final _logger = Logger('DeclarativeSqliteGenerator');
  final BuilderOptions options;

  DeclarativeSqliteGenerator(this.options);

  @override
  Future<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) async {
    _logger.info('=== DeclarativeSqliteGenerator.generateForAnnotatedElement START ===');
    _logger.info('Processing element: ${element.name}');

    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '`@GenerateDbRecord` can only be used on classes.',
        element: element,
      );
    }

    final tableName = annotation.read('tableName').stringValue;
    _logger.info('Extracted table name from annotation: "$tableName"');

    try {
      final schema = await _loadCachedSchema(buildStep);
      _logger.info('Schema loaded with ${schema.tables.length} tables.');

      final table = schema.tables.firstWhere(
        (t) => t.name == tableName,
        orElse: () {
          throw InvalidGenerationSourceError(
            'Table "$tableName" not found in schema. Available tables: ${schema.tables.map((t) => t.name).join(', ')}',
            element: element,
          );
        },
      );

      return _generateRecordClass(element, table);
    } catch (e, st) {
      _logger.severe('Error generating for $tableName: $e\n$st');
      rethrow;
    }
  }

  /// Loads the schema from the JSON cache.
  Future<Schema> _loadCachedSchema(BuildStep buildStep) async {
    final cacheAssetId = AssetId(buildStep.inputId.package, 'schema_cache.json');

    if (!await buildStep.canRead(cacheAssetId)) {
      throw InvalidGenerationSourceError(
        'Schema cache not found. The schema_generator builder must run first.',
      );
    }

    final jsonContent = await buildStep.readAsString(cacheAssetId);
    final jsonMap = jsonDecode(jsonContent) as Map<String, dynamic>;
    return Schema.fromJson(jsonMap);
  }

  /// Generates the extension with typed properties for the record class.
  String _generateRecordClass(ClassElement element, DbTable table) {
    final className = element.name;
    _logger.info('Generating record class for $className with table ${table.name}');
    final buffer = StringBuffer();

    buffer.writeln('/// Extension for $className with typed property access.');
    buffer.writeln('extension ${className}Properties on $className {');

    for (final column in table.columns) {
      final propertyName = _camelCase(column.name);
      final dartType = _getDartTypeForColumn(column.logicalType, column.isNotNull);
      final getterMethod = _getGetterMethodForColumn(column.logicalType, column.isNotNull);
      final setterMethod = _getSetterMethodForColumn(column.logicalType);

      buffer.writeln('  /// Gets the ${column.name} value.');
      buffer.writeln('  $dartType get $propertyName => $getterMethod(\'${column.name}\');');
      buffer.writeln();

      buffer.writeln('  /// Sets the ${column.name} value.');
      buffer.writeln('  set $propertyName($dartType value) => $setterMethod(\'${column.name}\', value);');
      buffer.writeln();
    }

    buffer.writeln('}');
    _logger.info('Generated extension with ${table.columns.length} properties.');
    return buffer.toString();
  }

  /// Converts snake_case to camelCase.
  String _camelCase(String input) {
    final parts = input.split('_');
    if (parts.isEmpty) return input;

    return parts.first.toLowerCase() +
        parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase()).join('');
  }

  /// Gets the Dart type for a column's logical type.
  String _getDartTypeForColumn(String logicalType, bool isNotNull) {
    final baseType = switch (logicalType) {
      'text' || 'guid' => 'String',
      'integer' => 'int',
      'real' => 'double',
      'date' => 'DateTime',
      'fileset' => 'FilesetField',
      _ => 'Object',
    };
    return isNotNull ? baseType : '$baseType?';
  }

  /// Gets the record's getter method for a column's logical type.
  String _getGetterMethodForColumn(String logicalType, bool isNotNull) {
    return switch (logicalType) {
      'text' || 'guid' => isNotNull ? 'getTextNotNull' : 'getText',
      'integer' => isNotNull ? 'getIntegerNotNull' : 'getInteger',
      'real' => isNotNull ? 'getRealNotNull' : 'getReal',
      'date' => isNotNull ? 'getDateTimeNotNull' : 'getDateTime',
      'fileset' => isNotNull ? 'getFilesetFieldNotNull' : 'getFilesetField',
      _ => 'getValue',
    };
  }

  /// Gets the record's setter method for a column's logical type.
  String _getSetterMethodForColumn(String logicalType) {
    return switch (logicalType) {
      'text' || 'guid' => 'setText',
      'integer' => 'setInteger',
      'real' => 'setReal',
      'date' => 'setDateTime',
      'fileset' => 'setFilesetField',
      _ => 'setValue',
    };
  }
}
