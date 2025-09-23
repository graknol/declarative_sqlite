import 'package:declarative_sqlite/src/schema/key.dart';

class KeyBuilder {
  final List<String> columns;
  KeyType _type = KeyType.indexed;
  String? _foreignTable;
  List<String>? _foreignColumns;

  KeyBuilder(this.columns);

  void primary() {
    _type = KeyType.primary;
  }

  void index() {
    _type = KeyType.indexed;
  }

  void unique() {
    _type = KeyType.unique;
  }

  void foreignKey(String table, List<String> columns) {
    _type = KeyType.foreign;
    _foreignTable = table;
    _foreignColumns = columns;
  }

  Key build() {
    return Key(
      columns: columns,
      type: _type,
      foreignTable: _foreignTable,
      foreignColumns: _foreignColumns,
    );
  }
}
