import 'package:declarative_sqlite/src/schema/column.dart';
import 'package:declarative_sqlite/src/schema/key.dart';
import 'package:declarative_sqlite/src/schema/reference.dart';

class Table {
  final String name;
  final List<Column> columns;
  final List<Key> keys;
  final List<Reference> references;

  const Table({
    required this.name,
    required this.columns,
    required this.keys,
    required this.references,
  });

  Table copyWith({
    String? name,
    List<Column>? columns,
    List<Key>? keys,
    List<Reference>? references,
  }) {
    return Table(
      name: name ?? this.name,
      columns: columns ?? this.columns,
      keys: keys ?? this.keys,
      references: references ?? this.references,
    );
  }
}
