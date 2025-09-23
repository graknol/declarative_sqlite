/// Represents dependencies of a query component
class QueryDependencies {
  final Set<String> tables;
  final Set<QueryDependencyColumn> columns;
  final bool usesWildcard;

  const QueryDependencies({
    required this.tables,
    required this.columns,
    required this.usesWildcard,
  });

  QueryDependencies.empty() : tables = {}, columns = {}, usesWildcard = false;

  /// Merges this dependencies with another
  QueryDependencies merge(QueryDependencies other) {
    return QueryDependencies(
      tables: {...tables, ...other.tables},
      columns: {...columns, ...other.columns},
      usesWildcard: usesWildcard || other.usesWildcard,
    );
  }
}

class QueryDependencyColumn {
  final String table;
  final String column;

  QueryDependencyColumn(this.table, this.column);

  /// Returns true if this column reference is qualified (has a table name)
  bool get isQualified => table.isNotEmpty;

  /// Returns the fully qualified column name (table.column)
  String get qualifiedName => isQualified ? '$table.$column' : column;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QueryDependencyColumn &&
           other.table == table &&
           other.column == column;
  }

  @override
  int get hashCode => Object.hash(table, column);

  @override
  String toString() => 'QueryDependencyColumn(table: $table, column: $column)';
}