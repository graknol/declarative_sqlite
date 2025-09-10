import 'package:meta/meta.dart';
import 'data_types.dart';

/// Builder for defining column specifications in a table schema.
/// 
/// Supports the fluent builder pattern for easy column definition with
/// data types, constraints, and default values.
@immutable
class ColumnBuilder {
  const ColumnBuilder._({
    required this.name,
    required this.dataType,
    this.constraints = const [],
    this.defaultValue,
  });

  /// Creates a new column with the specified name and data type.
  ColumnBuilder(this.name, this.dataType) : 
    constraints = const [], 
    defaultValue = null;

  /// The column name
  final String name;
  
  /// The SQLite data type affinity
  final SqliteDataType dataType;
  
  /// List of constraints applied to this column
  final List<ConstraintType> constraints;
  
  /// Default value for the column (if any)
  final dynamic defaultValue;

  /// Adds a primary key constraint to this column
  ColumnBuilder primaryKey() {
    if (constraints.contains(ConstraintType.primaryKey)) {
      return this;
    }
    return ColumnBuilder._(
      name: name,
      dataType: dataType,
      constraints: [...constraints, ConstraintType.primaryKey],
      defaultValue: defaultValue,
    );
  }

  /// Adds a unique constraint to this column
  ColumnBuilder unique() {
    if (constraints.contains(ConstraintType.unique)) {
      return this;
    }
    return ColumnBuilder._(
      name: name,
      dataType: dataType,
      constraints: [...constraints, ConstraintType.unique],
      defaultValue: defaultValue,
    );
  }

  /// Adds a not null constraint to this column
  ColumnBuilder notNull() {
    if (constraints.contains(ConstraintType.notNull)) {
      return this;
    }
    return ColumnBuilder._(
      name: name,
      dataType: dataType,
      constraints: [...constraints, ConstraintType.notNull],
      defaultValue: defaultValue,
    );
  }

  /// Sets a default value for this column
  ColumnBuilder withDefaultValue(dynamic value) {
    return ColumnBuilder._(
      name: name,
      dataType: dataType,
      constraints: constraints,
      defaultValue: value,
    );
  }

  /// Generates the SQL column definition
  String toSql() {
    final buffer = StringBuffer();
    buffer.write('$name $dataType');
    
    for (final constraint in constraints) {
      buffer.write(' $constraint');
    }
    
    if (defaultValue != null) {
      if (dataType == SqliteDataType.text) {
        buffer.write(" DEFAULT '${defaultValue.toString()}'");
      } else {
        buffer.write(' DEFAULT ${defaultValue.toString()}');
      }
    }
    
    return buffer.toString();
  }

  @override
  String toString() => toSql();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColumnBuilder &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          dataType == other.dataType &&
          _listEquals(constraints, other.constraints) &&
          defaultValue == other.defaultValue;

  @override
  int get hashCode =>
      name.hashCode ^
      dataType.hashCode ^
      constraints.hashCode ^
      defaultValue.hashCode;

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}