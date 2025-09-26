import 'package:declarative_sqlite/src/schema/db_key.dart';

class KeyBuilder {
  final List<String> columns;
  KeyType _type = KeyType.indexed;

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

  DbKey build() {
    return DbKey(
      columns: columns,
      type: _type,
    );
  }
}
