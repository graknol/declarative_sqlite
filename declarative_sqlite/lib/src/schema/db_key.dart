enum KeyType { primary, indexed, unique, foreign }

class DbKey {
  final List<String> columns;
  final KeyType type;
  final String? foreignTable;
  final List<String>? foreignColumns;

  const DbKey({
    required this.columns,
    required this.type,
    this.foreignTable,
    this.foreignColumns,
  });

  bool get isPrimary => type == KeyType.primary;
  bool get isUnique => type == KeyType.unique;
  bool get isForeign => type == KeyType.foreign;

  Map<String, dynamic> toMap() {
    return {
      'columns': columns,
      'type': type.toString(),
      'foreignTable': foreignTable,
      'foreignColumns': foreignColumns,
    };
  }

  Map<String, dynamic> toJson() => {
        'columns': columns,
        'type': type.toString(),
        'foreignTable': foreignTable,
        'foreignColumns': foreignColumns,
      };

  factory DbKey.fromJson(Map<String, dynamic> json) => DbKey(
        columns: (json['columns'] as List)
            .map((c) => c as String)
            .toList(),
        type: KeyType.values.firstWhere((e) => e.toString() == json['type']),
        foreignTable: json['foreignTable'],
        foreignColumns: (json['foreignColumns'] as List?)
            ?.map((c) => c as String)
            .toList(),
      );
}
