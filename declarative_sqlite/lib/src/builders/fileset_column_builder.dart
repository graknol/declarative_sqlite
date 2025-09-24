import 'column_builder.dart';
import '../schema/db_column.dart';

class FilesetColumnBuilder extends ColumnBuilder {
  FilesetColumnBuilder(String name) : super(name, 'fileset', 'TEXT');

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
    );
  }
}
