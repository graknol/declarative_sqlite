import 'package:declarative_sqlite/src/builders/column_builder.dart';

class DateColumnBuilder extends ColumnBuilder {
  DateColumnBuilder(String name) : super(name, 'date');
}
