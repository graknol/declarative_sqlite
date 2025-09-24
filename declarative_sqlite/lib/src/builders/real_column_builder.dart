import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/schema/db_column.dart';

class RealColumnBuilder extends ColumnBuilder {
  num? _minValue;
  num? _maxValue;

  RealColumnBuilder(String name) : super(name, 'real', 'REAL');

  RealColumnBuilder min(num value) {
    _minValue = value;
    return this;
  }

  RealColumnBuilder max(num value) {
    _maxValue = value;
    return this;
  }

  @override
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
      minValue: _minValue,
      maxValue: _maxValue,
    );
  }
}
