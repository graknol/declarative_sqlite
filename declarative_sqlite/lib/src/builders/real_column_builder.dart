import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/schema/column.dart';

class RealColumnBuilder extends ColumnBuilder {
  num? _minValue;
  num? _maxValue;

  RealColumnBuilder(String name) : super(name, 'real');

  RealColumnBuilder min(num value) {
    _minValue = value;
    return this;
  }

  RealColumnBuilder max(num value) {
    _maxValue = value;
    return this;
  }

  @override
  Column build() {
    return Column(
      name: name,
      type: type,
      isNotNull: isNotNull,
      isParent: isParent,
      isLww: isLww,
      minValue: _minValue,
      maxValue: _maxValue,
    );
  }
}
