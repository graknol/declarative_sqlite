import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:logging/logging.dart';
import 'package:source_gen/source_gen.dart';
import 'package:path/path.dart' as p;

import 'registration_aggregator.dart';
import 'registration_scanner.dart';

Builder declarativeSqliteGenerator(BuilderOptions options) =>
    PartBuilder([DeclarativeSqliteGenerator(options)], '.db.dart');

Builder registrationScanner(BuilderOptions options) =>
    RegistrationScanner();

Builder registrationAggregator(BuilderOptions options) =>
    RegistrationAggregator();

class DeclarativeSqliteGenerator extends GeneratorForAnnotation<GenerateDbRecord> {
  static final _logger = Logger('DeclarativeSqliteGenerator');
  final BuilderOptions options;

  DeclarativeSqliteGenerator(this.options);
  
  @override
  Future<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) async {
    _logger.info('=== DeclarativeSqliteGenerator.generateForAnnotatedElement START ===');
    _logger.info('Processing element: ${element.name} (${element.runtimeType})');
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '`@GenerateDbRecord` can only be used on classes.',
        element: element,
      );
    }

    final buffer = StringBuffer();
    final tableName = annotation.read('tableName').stringValue;
    _logger.info('Extracted table name from annotation: "$tableName"');

    final schema = await _getSchema(buildStep);
    _logger.info('Schema loaded with ${schema.tables.length} tables: ${schema.tables.map((t) => t.name).join(', ')}');
    
    final table = schema.tables.firstWhere((t) => t.name == tableName,
        orElse: () {
          _logger.severe('Table "$tableName" not found in schema. Available tables: ${schema.tables.map((t) => t.name).join(', ')}');
          throw InvalidGenerationSourceError(
              'Table "$tableName" not found in schema.',
              element: element);
        });
    
    _logger.info('Found table "$tableName" with ${table.columns.length} columns');
    for (final col in table.columns) {
      _logger.fine('  Column: ${col.name} (${col.logicalType}, notNull: ${col.isNotNull})');
    }

    _logger.info('Generating record class...');
    buffer.writeln(_generateRecordClass(element, table));
    buffer.writeln();

    final result = buffer.toString();
    _logger.info('Generated ${result.split('\n').length} lines of code');
    _logger.info('=== DeclarativeSqliteGenerator.generateForAnnotatedElement END ===');
    return result;
  }

  Future<Schema> _getSchema(BuildStep buildStep) async {
    final schemaPath = options.config['schema_definition_file'] as String?;
    if (schemaPath == null) {
      throw InvalidGenerationSourceError(
        'Missing `schema_definition_file` in build.yaml options.',
      );
    }

    final schemaAssetId = AssetId.parse(schemaPath);
    if (!await buildStep.canRead(schemaAssetId)) {
      throw InvalidGenerationSourceError(
        'Cannot find schema definition file at "$schemaPath".',
      );
    }

    // Create a temporary file to execute
    final tempDir = await Directory.systemTemp.createTemp('declarative_sqlite_generator');
    final tempFile = File(p.join(tempDir.path, 'schema_generator.dart'));
    final schemaJsonFile = File(p.join(tempDir.path, 'schema.json'));
    final packageConfigFile = File(p.join(Directory.current.path, '.dart_tool', 'package_config.json'));

    if (!await packageConfigFile.exists()) {
      throw Exception('Could not find .dart_tool/package_config.json. Please run `dart pub get`.');
    }

    try {
      final schemaLibrary = await buildStep.resolver.libraryFor(schemaAssetId);
      final schemaFunction = schemaLibrary.definingCompilationUnit.functions
          .firstWhere(
            (e) => e.returnType.getDisplayString(withNullability: false) == 'void' &&
                   e.parameters.length == 1 &&
                   e.parameters.first.type.getDisplayString(withNullability: false) == 'SchemaBuilder',
            orElse: () => throw InvalidGenerationSourceError(
              'No valid schema definition function found in "$schemaPath". '
              'Expected a function like: `void defineSchema(SchemaBuilder builder) { ... }`',
            ),
          );

      final fileContent = '''
import 'dart:convert';
import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import '${schemaAssetId.uri}' as schema_def;

void main() async {
  final builder = SchemaBuilder();
  schema_def.${schemaFunction.name}(builder);
  final schema = builder.build();
  final jsonString = jsonEncode(schema.toJson());
  await File('${p.toUri(schemaJsonFile.path)}').writeAsString(jsonString);
}
''';

      await tempFile.writeAsString(fileContent);

      // Execute the temporary file
      final result = await Process.run(
        'dart',
        ['--packages=${p.toUri(packageConfigFile.path)}', tempFile.path],
        workingDirectory: Directory.current.path,
      );

      if (result.exitCode != 0) {
        _logger.severe('Failed to generate schema JSON. Error: ${result.stderr}');
        throw Exception('Failed to generate schema JSON: ${result.stderr}');
      }

      // Read the generated JSON
      final jsonString = await schemaJsonFile.readAsString();
      if (jsonString.isEmpty) {
        _logger.warning('Generated schema.json is empty. Returning an empty schema.');
        return Schema(tables: [], views: []);
      }
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return Schema.fromJson(jsonMap);
    } catch (e, st) {
      _logger.severe('Error during schema generation: $e\n$st');
      rethrow;
    }
    finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// Generates typed properties extension
  String _generateRecordClass(ClassElement element, DbTable schemaTable) {
    final className = element.name;
    _logger.info('Generating record class for $className with table ${schemaTable.name}');
    final buffer = StringBuffer();

    // Generate extension for typed properties
    buffer.writeln('/// Generated typed properties for $className');
    buffer.writeln('extension ${className}Generated on $className {');

    _logger.info('Generating getters and setters for ${schemaTable.columns.length} columns');
    _generateGettersAndSetters(buffer, schemaTable);

    buffer.writeln('}');

    _logger.info('Completed record class generation for $className');
    return buffer.toString();
  }

  /// Generates getters and setters based on the actual schema table
  void _generateGettersAndSetters(StringBuffer buffer, DbTable table) {
    final primaryKeyColumns =
        table.keys.where((k) => k.isPrimary).expand((k) => k.columns).toSet();

    buffer.writeln('  // Generated getters and setters');
    for (final col in table.columns) {
      final propertyName = _camelCase(col.name);
      final dartType = _getDartTypeForColumn(col.logicalType, col.isNotNull);
      final getterMethod =
          _getGetterMethodForColumn(col.logicalType, col.isNotNull);

      buffer.writeln('  /// Gets the ${col.name} column value.');
      buffer.writeln(
          '  $dartType get $propertyName => $getterMethod(\'${col.name}\');');

      // Make properties from primary keys immutable (no setter)
      if (primaryKeyColumns.contains(col.name)) {
        continue;
      }

      final setterMethod = _getSetterMethodForColumn(col.logicalType);
      buffer.writeln('  /// Sets the ${col.name} column value.');
      buffer.writeln(
          '  set $propertyName($dartType value) => $setterMethod(\'${col.name}\', value);');
      buffer.writeln();
    }
  }

  /// Gets the Dart type for a column type
  String _getDartTypeForColumn(String logicalType, bool notNull) {
    final baseType = switch (logicalType) {
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
  String _getGetterMethodForColumn(String logicalType, bool notNull) {
    return switch (logicalType) {
      'text' || 'guid' => notNull ? 'getTextNotNull' : 'getText',
      'integer' => notNull ? 'getIntegerNotNull' : 'getInteger',
      'real' => notNull ? 'getRealNotNull' : 'getReal',
      'date' => notNull ? 'getDateTimeNotNull' : 'getDateTime',
      'fileset' => notNull ? 'getFilesetFieldNotNull' : 'getFilesetField',
      _ => 'getValue',
    };
  }

  /// Gets the setter method name for a column type
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
