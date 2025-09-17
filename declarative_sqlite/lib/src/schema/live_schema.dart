class LiveSchema {
  final List<LiveTable> tables;
  final List<LiveView> views;

  Iterable<LiveTable> get userTables => tables.where((t) => !t.isSystem);
  Iterable<LiveTable> get systemTables => tables.where((t) => t.isSystem);

  LiveSchema({required this.tables, required this.views});
}

class LiveTable {
  final String name;
  final List<LiveColumn> columns;
  final List<LiveKey> keys;

  bool get isSystem => name.startsWith('__');

  LiveTable({
    required this.name,
    required this.columns,
    required this.keys,
  });
}

class LiveView {
  final String name;
  final String sql;

  LiveView({required this.name, required this.sql});
}

class LiveColumn {
  final String name;
  final String type;
  final bool isNotNull;
  final bool isPrimaryKey;
  final String? defaultValue;

  LiveColumn({
    required this.name,
    required this.type,
    required this.isNotNull,
    required this.isPrimaryKey,
    this.defaultValue,
  });
}

class LiveKey {
  final String name;
  final List<String> columns;
  final bool isUnique;

  LiveKey({required this.name, required this.columns, required this.isUnique});
}
