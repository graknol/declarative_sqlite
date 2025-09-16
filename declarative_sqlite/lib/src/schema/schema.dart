import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/schema/view.dart';

class Schema {
  final int version;
  final List<Table> tables;
  final List<View> views;

  const Schema({
    required this.version,
    required this.tables,
    required this.views,
  });
}
