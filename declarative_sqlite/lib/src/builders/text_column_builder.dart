import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/schema/db_column.dart';

class TextColumnBuilder extends ColumnBuilder {
  int? _maxLength;

  TextColumnBuilder(String name) : super(name, 'text', 'TEXT');

  TextColumnBuilder maxLength(int value) {
    _maxLength = value;
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
      maxLength: _maxLength,
    );
  }
}
