import 'package:code_builder/code_builder.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Generates data classes for table rows based on TableBuilder metadata.
class TableDataClassGenerator {
  const TableDataClassGenerator();
  /// Generates a data class for the given table.
  Class generateDataClass(TableBuilder table) {
    final className = _toDataClassName(table.name);
    
    return Class((b) => b
      ..name = className
      ..docs.addAll([
        '/// Data class for ${table.name} table rows.',
        '/// Generated from TableBuilder metadata.',
      ])
      ..constructors.add(_generateConstructor(table))
      ..fields.addAll(_generateFields(table))
      ..methods.addAll(_generateMethods(table, className))
    );
  }

  /// Generates the main constructor with named parameters.
  Constructor _generateConstructor(TableBuilder table) {
    return Constructor((b) => b
      ..constant = true
      ..optionalParameters.addAll(
        table.columns.map((column) => Parameter((p) => p
          ..name = column.name
          ..toThis = true
          ..named = true
          ..required = _isColumnRequired(column)
        )),
      )
    );
  }

  /// Generates fields for all table columns.
  List<Field> _generateFields(TableBuilder table) {
    return table.columns.map((column) => Field((f) => f
      ..name = column.name
      ..type = _dartTypeForColumn(column)
      ..modifier = FieldModifier.final$
      ..docs.add('/// ${column.name} column (${column.dataType})')
    )).toList();
  }

  /// Generates utility methods: toMap, fromMap, toString, hashCode, ==
  List<Method> _generateMethods(TableBuilder table, String className) {
    return [
      _generateToMapMethod(table),
      _generateFromMapMethod(table, className),
      _generateToStringMethod(table, className),
      _generateHashCodeMethod(table),
      _generateEqualsMethod(table, className),
    ];
  }

  /// Generates toMap() method for database serialization.
  Method _generateToMapMethod(TableBuilder table) {
    final mapEntries = table.columns.map((column) => 
      "'${column.name}': ${column.name}").join(', ');
    
    return Method((b) => b
      ..name = 'toMap'
      ..returns = refer('Map<String, dynamic>')
      ..docs.add('/// Converts this data object to a map for database storage.')
      ..body = Code('return {$mapEntries};')
    );
  }

  /// Generates fromMap() static method for database deserialization.
  Method _generateFromMapMethod(TableBuilder table, String className) {
    final constructorArgs = table.columns.map((column) {
      final typeName = _dartTypeForColumn(column).symbol;
      if (_isColumnRequired(column)) {
        return "${column.name}: map['${column.name}'] as $typeName";
      } else {
        return "${column.name}: map['${column.name}'] as $typeName";
      }
    }).join(', ');
    
    return Method((b) => b
      ..name = 'fromMap'
      ..static = true
      ..returns = refer(className)
      ..requiredParameters.add(Parameter((p) => p
        ..name = 'map'
        ..type = refer('Map<String, dynamic>')
      ))
      ..docs.add('/// Creates a data object from a database map.')
      ..body = Code('return $className($constructorArgs);')
    );
  }

  /// Generates toString() method.
  Method _generateToStringMethod(TableBuilder table, String className) {
    final fieldsList = table.columns.map((c) => '${c.name}: \$${c.name}').join(', ');
    
    return Method((b) => b
      ..name = 'toString'
      ..returns = refer('String')
      ..annotations.add(refer('override'))
      ..docs.add('/// String representation of this data object.')
      ..body = refer("'$className($fieldsList)'").code
    );
  }

  /// Generates hashCode getter.
  Method _generateHashCodeMethod(TableBuilder table) {
    final hashFields = table.columns.map((c) => '${c.name}.hashCode').join(' ^ ');
    
    return Method((b) => b
      ..name = 'hashCode'
      ..type = MethodType.getter
      ..returns = refer('int')
      ..annotations.add(refer('override'))
      ..docs.add('/// Hash code for this data object.')
      ..body = Code('return $hashFields;')
    );
  }

  /// Generates == operator.
  Method _generateEqualsMethod(TableBuilder table, String className) {
    final equalityChecks = table.columns
        .map((c) => 'other.${c.name} == ${c.name}')
        .join(' && ');
    
    return Method((b) => b
      ..name = 'operator =='
      ..returns = refer('bool')
      ..annotations.add(refer('override'))
      ..requiredParameters.add(Parameter((p) => p
        ..name = 'other'
        ..type = refer('Object')
      ))
      ..docs.add('/// Equality comparison for this data object.')
      ..body = Code('return identical(this, other) || (other is $className && $equalityChecks);')
    );
  }

  /// Converts table name to PascalCase data class name.
  String _toDataClassName(String tableName) {
    // Convert snake_case to PascalCase and add "Data" suffix
    final words = tableName.split('_');
    final pascalCase = words.map((word) => 
      word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase()
    ).join('');
    return '${pascalCase}Data';
  }

  /// Gets the appropriate Dart type for a column.
  Reference _dartTypeForColumn(ColumnBuilder column) {
    final baseTypeName = switch (column.dataType) {
      SqliteDataType.integer => 'int',
      SqliteDataType.real => 'double',
      SqliteDataType.text => 'String',
      SqliteDataType.blob => 'List<int>',
      SqliteDataType.date => 'DateTime',
      SqliteDataType.fileset => 'String', // Fileset stored as text
    };
    
    // Make nullable if column is not required
    if (_isColumnRequired(column)) {
      return refer(baseTypeName);
    } else {
      return refer('$baseTypeName?');
    }
  }

  /// Checks if a column is required (not null).
  bool _isColumnRequired(ColumnBuilder column) {
    return column.constraints.contains(ConstraintType.notNull) ||
           column.constraints.contains(ConstraintType.primaryKey);
  }
}