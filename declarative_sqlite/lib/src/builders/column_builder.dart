import 'package:declarative_sqlite/src/schema/db_column.dart';
import 'package:meta/meta.dart';

/// Base class for all column builders.
abstract class ColumnBuilder {
  final String name;
  final String logicalType;
  final String dbType;

  @protected
  bool isNotNull = false;
  @protected
  bool isParent = false;
  @protected
  bool isLww = false;
  @protected
  Object? defaultValue;
  @protected
  DefaultValueCallback? defaultValueCallback;

  ColumnBuilder(this.name, this.logicalType, this.dbType);

  ColumnBuilder notNull([Object? defaultValue]) {
    isNotNull = true;
    this.defaultValue = defaultValue;
    return this;
  }

  ColumnBuilder parent() {
    isParent = true;
    return this;
  }

  ColumnBuilder lww() {
    isLww = true;
    return this;
  }

  ColumnBuilder defaultsTo(Object? value) {
    defaultValue = value;
    defaultValueCallback = null; // Clear callback when setting static value
    return this;
  }

  /// Sets a callback function to generate default values on-the-fly
  /// The callback is called each time a record is inserted without a value for this column
  ColumnBuilder defaultCallback(DefaultValueCallback callback) {
    defaultValueCallback = callback;
    defaultValue = null; // Clear static value when setting callback
    return this;
  }

  DbColumn build() {
    return DbColumn(
      name: name,
      logicalType: logicalType,
      type: dbType,
      isNotNull: isNotNull,
      defaultValue: defaultValue,
      defaultValueCallback: defaultValueCallback,
      isParent: isParent,
      isLww: isLww,
    );
  }
}
