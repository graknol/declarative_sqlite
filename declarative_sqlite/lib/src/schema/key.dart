enum KeyType { primary, indexed, unique, foreign }

class Key {
  final List<String> columns;
  final KeyType type;
  final String? foreignTable;
  final List<String>? foreignColumns;

  const Key({
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
}
