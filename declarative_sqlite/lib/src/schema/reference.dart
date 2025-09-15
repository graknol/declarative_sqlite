enum ReferenceType { toOne, toMany }

class Reference {
  final List<String> columns;
  final String foreignTable;
  final List<String> foreignColumns;
  final ReferenceType type;

  const Reference({
    required this.columns,
    required this.foreignTable,
    required this.foreignColumns,
    required this.type,
  });
}
