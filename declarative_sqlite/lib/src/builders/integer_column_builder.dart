import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/schema/column.dart';

class IntegerColumnBuilder extends ColumnBuilder {
  num? _minValue;
  num? _maxValue;
  bool _isSequence = false;
  bool _sequencePerParent = false;

  IntegerColumnBuilder(String name) : super(name, 'integer');

  IntegerColumnBuilder min(num value) {
    _minValue = value;
    return this;
  }

  IntegerColumnBuilder max(num value) {
    _maxValue = value;
    return this;
  }

  IntegerColumnBuilder sequence({bool perParent = false}) {
    _isSequence = true;
    _sequencePerParent = perParent;
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
      isSequence: _isSequence,
      sequencePerParent: _sequencePerParent,
    );
  }
}
