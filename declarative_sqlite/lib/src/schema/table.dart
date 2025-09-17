import 'package:declarative_sqlite/src/schema/column.dart';
import 'package:declarative_sqlite/src/schema/key.dart';

class Table {
  final String name;
  final List<Column> columns;
  final List<Key> keys;

  bool get isSystem => name.startsWith('__');

  const Table({
    required this.name,
    required this.columns,
    required this.keys,
  });

  Table copyWith({
    String? name,
    List<Column>? columns,
    List<Key>? keys,
  }) {
    return Table(
      name: name ?? this.name,
      columns: columns ?? this.columns,
      keys: keys ?? this.keys,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'columns': columns.map((c) => c.toMap()).toList(),
      'keys': keys.map((k) => k.toMap()).toList(),
    };
  }
}
