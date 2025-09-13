import 'package:meta/meta.dart';

/// Builder for defining index specifications on table columns.
/// 
/// Supports both single-column and composite indices with unique option.
@immutable
class IndexBuilder {
  const IndexBuilder._({
    required this.name,
    required this.tableName,
    required this.columns,
    required this.unique,
  });

  /// Creates a new index builder for the specified table and columns.
  /// 
  /// [name] is the index name, [tableName] is the target table,
  /// and [columns] are the column names to index.
  IndexBuilder(this.name, this.tableName, this.columns) : unique = false;

  /// Creates a new single-column index
  IndexBuilder.single(String name, String tableName, String column)
      : this(name, tableName, [column]);

  /// The index name
  final String name;
  
  /// The table this index applies to
  final String tableName;
  
  /// List of column names that make up this index
  final List<String> columns;
  
  /// Whether this is a unique index
  final bool unique;

  /// Makes this index unique
  IndexBuilder makeUnique() {
    if (unique) return this;
    
    return IndexBuilder._(
      name: name,
      tableName: tableName,
      columns: columns,
      unique: true,
    );
  }

  /// Generates the SQL CREATE INDEX statement
  String toSql() {
    final buffer = StringBuffer();
    
    buffer.write('CREATE ');
    if (unique) {
      buffer.write('UNIQUE ');
    }
    buffer.write('INDEX $name ON $tableName (');
    buffer.write(columns.join(', '));
    buffer.write(')');
    
    return buffer.toString();
  }

  @override
  String toString() => toSql();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexBuilder &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          tableName == other.tableName &&
          _listEquals(columns, other.columns) &&
          unique == other.unique;

  @override
  int get hashCode =>
      name.hashCode ^
      tableName.hashCode ^
      columns.hashCode ^
      unique.hashCode;

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}