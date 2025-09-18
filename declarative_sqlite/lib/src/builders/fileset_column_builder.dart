import 'column_builder.dart';
import '../schema/column.dart';

class FilesetColumnBuilder extends ColumnBuilder {
  FilesetColumnBuilder(String name) : super(name, 'fileset', 'TEXT');

  @override
  Column build() {
    return Column(
      name: name,
      logicalType: logicalType,
      type: dbType,
      isNotNull: isNotNull,
      defaultValue: defaultValue,
    );
  }
}
