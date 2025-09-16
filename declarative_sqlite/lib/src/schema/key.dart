enum KeyType { primary, indexed }

class Key {
  final List<String> columns;
  final KeyType type;

  const Key({
    required this.columns,
    required this.type,
  });

  bool get isPrimary => type == KeyType.primary;

  Map<String, dynamic> toMap() {
    return {
      'columns': columns,
      'type': type.toString(),
    };
  }
}
