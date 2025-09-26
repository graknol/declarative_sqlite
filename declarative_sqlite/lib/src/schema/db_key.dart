enum KeyType { primary, indexed, unique }

class DbKey {
  final List<String> columns;
  final KeyType type;

  const DbKey({
    required this.columns,
    required this.type,
  });

  bool get isPrimary => type == KeyType.primary;
  bool get isUnique => type == KeyType.unique;

  Map<String, dynamic> toMap() {
    return {
      'columns': columns,
      'type': type.toString(),
    };
  }

  Map<String, dynamic> toJson() => {
        'columns': columns,
        'type': type.toString(),
      };

  factory DbKey.fromJson(Map<String, dynamic> json) => DbKey(
        columns: (json['columns'] as List)
            .map((c) => c as String)
            .toList(),
        type: KeyType.values.firstWhere((e) => e.toString() == json['type']),
      );
}
