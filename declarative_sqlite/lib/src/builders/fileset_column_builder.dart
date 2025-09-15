import 'package:declarative_sqlite/src/builders/column_builder.dart';
import 'package:declarative_sqlite/src/schema/column.dart';

class FilesetColumnBuilder extends ColumnBuilder {
  int? _maxFileSizeMb;
  int? _maxCount;

  FilesetColumnBuilder(String name) : super(name, 'fileset');

  FilesetColumnBuilder mb(int size) {
    _maxFileSizeMb = size;
    return this;
  }

  FilesetColumnBuilder max(int value) {
    _maxCount = value;
    return this;
  }

  FilesetColumnBuilder get maxFileSize => this;

  @override
  Column build() {
    return Column(
      name: name,
      type: type,
      isNotNull: isNotNull,
      isParent: isParent,
      isLww: isLww,
      maxFileSizeMb: _maxFileSizeMb,
      maxCount: _maxCount,
    );
  }
}
