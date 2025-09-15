import 'package:declarative_sqlite/src/builders/column_builder.dart';

class GuidColumnBuilder extends ColumnBuilder {
  GuidColumnBuilder(String name) : super(name, 'guid');
}
