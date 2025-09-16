class View {
  final String name;
  final String definition;

  const View({
    required this.name,
    required this.definition,
  });

  String toSql() {
    return 'CREATE VIEW $name AS $definition';
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'definition': definition,
    };
  }
}
