import 'package:declarative_sqlite/src/schema/reference.dart';

class ReferenceBuilder {
  final List<String> columns;
  late String _foreignTable;
  late List<String> _foreignColumns;
  late ReferenceType _type;

  ReferenceBuilder(this.columns);

  void to(String table, List<String> foreignColumns) {
    _foreignTable = table;
    _foreignColumns = foreignColumns;
    _type = ReferenceType.toOne;
  }

  void toMany(String table, List<String> foreignColumns) {
    _foreignTable = table;
    _foreignColumns = foreignColumns;
    _type = ReferenceType.toMany;
  }

  Reference build() {
    return Reference(
      columns: columns,
      foreignTable: _foreignTable,
      foreignColumns: _foreignColumns,
      type: _type,
    );
  }
}
