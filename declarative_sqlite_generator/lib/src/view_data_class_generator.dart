import 'package:code_builder/code_builder.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Generates data classes for view rows based on ViewBuilder metadata.
class ViewDataClassGenerator {
  const ViewDataClassGenerator();
  /// Generates a data class for the given view.
  Class generateDataClass(ViewBuilder view, SchemaBuilder schema) {
    final className = _toDataClassName(view.name);
    final columns = _extractViewColumns(view, schema);
    
    return Class((b) => b
      ..name = className
      ..docs.addAll([
        '/// Data class for ${view.name} view rows.',
        '/// Generated from ViewBuilder metadata.',
      ])
      ..constructors.add(_generateConstructor(columns))
      ..fields.addAll(_generateFields(columns))
      ..methods.addAll(_generateMethods(columns, className))
    );
  }

  /// Extracts column information from a view.
  /// This is a simplified approach - in a real implementation, you might want
  /// to parse the SQL query to determine exact column types and nullability.
  List<ViewColumn> _extractViewColumns(ViewBuilder view, SchemaBuilder schema) {
    // For this example, we'll make some assumptions about view columns
    // In a production implementation, you would parse the SQL query
    
    if (view.isRawSql) {
      // For raw SQL views, we can't easily determine columns without parsing
      // Return a generic set of columns or require annotation
      return [
        ViewColumn('result', SqliteDataType.text, nullable: true),
      ];
    }
    
    // For query builder views, we could potentially analyze the query
    // For now, return common view columns
    return [
      ViewColumn('id', SqliteDataType.integer, nullable: false),
      ViewColumn('data', SqliteDataType.text, nullable: true),
    ];
  }

  /// Generates the main constructor with named parameters.
  Constructor _generateConstructor(List<ViewColumn> columns) {
    return Constructor((b) => b
      ..constant = true
      ..optionalParameters.addAll(
        columns.map((column) => Parameter((p) => p
          ..name = column.name
          ..toThis = true
          ..named = true
          ..required = !column.nullable
        )),
      )
    );
  }

  /// Generates fields for all view columns.
  List<Field> _generateFields(List<ViewColumn> columns) {
    return columns.map((column) => Field((f) => f
      ..name = column.name
      ..type = _dartTypeForColumn(column)
      ..modifier = FieldModifier.final$
      ..docs.add('/// ${column.name} column (${column.dataType})')
    )).toList();
  }

  /// Generates utility methods: fromMap, toString, hashCode, ==
  /// Note: Views are read-only, so no toMap() method is generated.
  List<Method> _generateMethods(List<ViewColumn> columns, String className) {
    return [
      _generateFromMapMethod(columns, className),
      _generateToStringMethod(columns, className),
      _generateHashCodeMethod(columns),
      _generateEqualsMethod(columns, className),
    ];
  }

  /// Generates fromMap() static method for database deserialization.
  Method _generateFromMapMethod(List<ViewColumn> columns, String className) {
    final constructorArgs = columns.map((column) {
      final typeName = _dartTypeForColumn(column).symbol;
      return "${column.name}: map['${column.name}'] as $typeName";
    }).join(', ');
    
    return Method((b) => b
      ..name = 'fromMap'
      ..static = true
      ..returns = refer(className)
      ..requiredParameters.add(Parameter((p) => p
        ..name = 'map'
        ..type = refer('Map<String, dynamic>')
      ))
      ..docs.add('/// Creates a data object from a view result map.')
      ..body = Code('return $className($constructorArgs);')
    );
  }

  /// Generates toString() method.
  Method _generateToStringMethod(List<ViewColumn> columns, String className) {
    final fieldsList = columns.map((c) => '${c.name}: \$${c.name}').join(', ');
    
    return Method((b) => b
      ..name = 'toString'
      ..returns = refer('String')
      ..annotations.add(refer('override'))
      ..docs.add('/// String representation of this view data object.')
      ..body = refer("'$className($fieldsList)'").code
    );
  }

  /// Generates hashCode getter.
  Method _generateHashCodeMethod(List<ViewColumn> columns) {
    final hashFields = columns.map((c) => '${c.name}.hashCode').join(' ^ ');
    
    return Method((b) => b
      ..name = 'hashCode'
      ..type = MethodType.getter
      ..returns = refer('int')
      ..annotations.add(refer('override'))
      ..docs.add('/// Hash code for this view data object.')
      ..body = Code('return $hashFields;')
    );
  }

  /// Generates == operator.
  Method _generateEqualsMethod(List<ViewColumn> columns, String className) {
    final equalityChecks = columns
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
      ..docs.add('/// Equality comparison for this view data object.')
      ..body = Code('return identical(this, other) || (other is $className && $equalityChecks);')
    );
  }

  /// Converts view name to PascalCase data class name.
  String _toDataClassName(String viewName) {
    // Convert snake_case to PascalCase and add "Data" suffix
    final words = viewName.split('_');
    final pascalCase = words.map((word) => 
      word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase()
    ).join('');
    return '${pascalCase}ViewData';
  }

  /// Gets the appropriate Dart type for a view column.
  Reference _dartTypeForColumn(ViewColumn column) {
    final baseTypeName = switch (column.dataType) {
      SqliteDataType.integer => 'int',
      SqliteDataType.real => 'double',
      SqliteDataType.text => 'String',
      SqliteDataType.blob => 'List<int>',
      SqliteDataType.date => 'DateTime',
      SqliteDataType.fileset => 'String', // Fileset stored as text
    };
    
    // Make nullable if column is nullable
    if (column.nullable) {
      return refer('$baseTypeName?');
    } else {
      return refer(baseTypeName);
    }
  }
}

/// Represents a column in a view for code generation.
class ViewColumn {
  const ViewColumn(this.name, this.dataType, {required this.nullable});
  
  final String name;
  final SqliteDataType dataType;
  final bool nullable;
}