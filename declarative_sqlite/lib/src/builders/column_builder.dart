import 'package:declarative_sqlite/src/schema/column.dart';
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

  ColumnBuilder(this.name, this.logicalType, this.dbType);

  ColumnBuilder notNull(Object defaultValue) {
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

  Column build() {
    return Column(
      name: name,
      logicalType: logicalType,
      type: dbType,
      isNotNull: isNotNull,
      defaultValue: defaultValue,
      isParent: isParent,
      isLww: isLww,
    );
  }
}
