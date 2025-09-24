import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/schema/db_column.dart';

class IntegerColumnBuilder extends ColumnBuilder {
  num? _minValue;
  num? _maxValue;

  IntegerColumnBuilder(String name) : super(name, 'integer', 'INTEGER');

  IntegerColumnBuilder min(num value) {
    _minValue = value;
    return this;
  }

  IntegerColumnBuilder max(num value) {
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
      isParent: isParent,
      isLww: isLww,
      minValue: _minValue,
      maxValue: _maxValue,
    );
  }
}
