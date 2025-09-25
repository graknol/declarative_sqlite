import 'package:declarative_sqlite/src/schema/db_column.dart';
import 'package:declarative_sqlite/src/schema/db_key.dart';

class DbTable {
  final String name;
  final List<DbColumn> columns;
  final List<DbKey> keys;

  bool get isSystem => name.startsWith('__');

  const DbTable({
    required this.name,
    required this.columns,
    required this.keys,
  });

  DbTable copyWith({
    String? name,
    List<DbColumn>? columns,
    List<DbKey>? keys,
  }) {
    return DbTable(
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

  Map<String, dynamic> toJson() => {
        'name': name,
        'columns': columns.map((c) => c.toJson()).toList(),
        'keys': keys.map((k) => k.toJson()).toList(),
      };

  factory DbTable.fromJson(Map<String, dynamic> json) => DbTable(
        name: json['name'],
        columns: (json['columns'] as List)
            .map((c) => DbColumn.fromJson(c))
            .toList(),
        keys: (json['keys'] as List)
            .map((k) => DbKey.fromJson(k))
            .toList(),
      );
}
