import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/schema/column.dart';

class TextColumnBuilder extends ColumnBuilder {
  int? _maxLength;

  TextColumnBuilder(String name) : super(name, 'text');

  TextColumnBuilder maxLength(int value) {
    _maxLength = value;
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
      maxLength: _maxLength,
    );
  }
}
