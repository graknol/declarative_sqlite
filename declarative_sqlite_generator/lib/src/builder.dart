import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:logging/logging.dart';
import 'package:source_gen/source_gen.dart';

import 'registration_aggregator.dart';
import 'registration_scanner.dart';

Builder declarativeSqliteGenerator(BuilderOptions options) =>
    PartBuilder([DeclarativeSqliteGenerator()], '.db.dart');

Builder registrationScanner(BuilderOptions options) =>
    RegistrationScanner();

Builder registrationAggregator(BuilderOptions options) =>
    RegistrationAggregator();

class DeclarativeSqliteGenerator extends GeneratorForAnnotation<GenerateDbRecord> {
  static final _logger = Logger('DeclarativeSqliteGenerator');
  
  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
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

    // This is a placeholder. A real implementation would need a way
    // to access the schema definition. For this example, we'll
    // assume a function `createAppSchema()` exists and can be used.
    // This part of the logic is complex and would require more robust
    // schema discovery.
    _logger.info('Creating app schema...');
    final schema = createAppSchema();
    _logger.info('Schema created with ${schema.tables.length} tables: ${schema.tables.map((t) => t.name).join(', ')}');
    
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

// A placeholder function to make the generator compile.
// In a real-world scenario, schema information would be accessed differently,
// possibly by analyzing the source code where the schema is defined.
Schema createAppSchema() {
  final builder = SchemaBuilder();
  builder.table('users', (table) {
    table.guid('id').notNull('');
    table.text('name').notNull('');
    table.text('email').notNull('');
    table.integer('age').notNull(0);
    table.date('created_at').notNull('');
    table.key(['id']).primary();
  });
  builder.table('posts', (table) {
    table.guid('id').notNull('');
    table.guid('user_id').notNull('');
    table.text('title').notNull('');
    table.text('content').notNull('');
    table.date('created_at').notNull('');
    table.text('user_name').notNull(''); // Denormalized for demo simplicity
    table.key(['id']).primary();
  });
  builder.table('comments', (table) {
    table.integer('id').notNull();
    table.integer('post_id').notNull();
    table.integer('user_id').notNull();
    table.text('comment').notNull();
    table.date('created_at').notNull();
    table.key(['id']).primary();
  });
  return builder.build();
}
