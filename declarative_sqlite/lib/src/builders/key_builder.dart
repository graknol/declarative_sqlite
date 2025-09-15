import 'package:declarative_sqlite/src/schema/key.dart';

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

  Key build() {
    return Key(columns: columns, type: _type);
  }
}
