import 'package:declarative_sqlite/src/schema/column.dart';
import 'package:meta/meta.dart';

/// Base class for all column builders.
abstract class ColumnBuilder {
  final String name;
  final String type;

  @protected
  bool isNotNull = false;
  @protected
  bool isParent = false;
  @protected
  bool isLww = false;

  ColumnBuilder(this.name, this.type);

  ColumnBuilder notNull() {
    isNotNull = true;
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
      type: type,
      isNotNull: isNotNull,
      isParent: isParent,
      isLww: isLww,
    );
  }
}
