import 'package:meta/meta.dart';
import 'column_builder.dart';
import 'index_builder.dart';
import 'data_types.dart';

/// Builder for defining table specifications in a database schema.
/// 
/// Supports the fluent builder pattern for defining tables with columns,
/// indices, and constraints.
@immutable
class TableBuilder {
  const TableBuilder._({
    required this.name,
    required this.columns,
    required this.indices,
  });

  /// Creates a new table builder with the specified name.
  TableBuilder(this.name) : 
    columns = const [], 
    indices = const [];

  /// The table name
  final String name;
  
  /// List of columns in this table
  final List<ColumnBuilder> columns;
  
  /// List of indices on this table
  final List<IndexBuilder> indices;

  /// Adds a column to this table with INTEGER data type
  TableBuilder integer(String columnName, [ColumnBuilder Function(ColumnBuilder)? configure]) {
    var column = ColumnBuilder(columnName, SqliteDataType.integer);
    if (configure != null) {
      column = configure(column);
    }
    return addColumn(column);
  }

  /// Adds a column to this table with REAL data type
  TableBuilder real(String columnName, [ColumnBuilder Function(ColumnBuilder)? configure]) {
    var column = ColumnBuilder(columnName, SqliteDataType.real);
    if (configure != null) {
      column = configure(column);
    }
    return addColumn(column);
  }

  /// Adds a column to this table with TEXT data type
  TableBuilder text(String columnName, [ColumnBuilder Function(ColumnBuilder)? configure]) {
    var column = ColumnBuilder(columnName, SqliteDataType.text);
    if (configure != null) {
      column = configure(column);
    }
    return addColumn(column);
  }

  /// Adds a column to this table with BLOB data type
  TableBuilder blob(String columnName, [ColumnBuilder Function(ColumnBuilder)? configure]) {
    var column = ColumnBuilder(columnName, SqliteDataType.blob);
    if (configure != null) {
      column = configure(column);
    }
    return addColumn(column);
  }

  /// Adds a pre-built column to this table
  TableBuilder addColumn(ColumnBuilder column) {
    // Check for duplicate column names
    if (columns.any((c) => c.name == column.name)) {
      throw ArgumentError('Column "${column.name}" already exists in table "$name"');
    }
    
    return TableBuilder._(
      name: name,
      columns: [...columns, column],
      indices: indices,
    );
  }

  /// Adds an index to this table
  TableBuilder addIndex(IndexBuilder index) {
    // Validate that all indexed columns exist in the table
    for (final columnName in index.columns) {
      if (!columns.any((c) => c.name == columnName)) {
        throw ArgumentError(
          'Cannot create index "${index.name}": column "$columnName" does not exist in table "$name"'
        );
      }
    }
    
    // Check for duplicate index names
    if (indices.any((i) => i.name == index.name)) {
      throw ArgumentError('Index "${index.name}" already exists in table "$name"');
    }
    
    return TableBuilder._(
      name: name,
      columns: columns,
      indices: [...indices, index],
    );
  }

  /// Creates an index on this table with one or more columns
  TableBuilder index(String indexName, List<String> columnNames, {bool unique = false}) {
    var indexBuilder = IndexBuilder(indexName, name, columnNames);
    if (unique) {
      indexBuilder = indexBuilder.makeUnique();
    }
    return addIndex(indexBuilder);
  }

  /// Convenience method to add a primary key column
  TableBuilder primaryKey(String columnName, SqliteDataType dataType) {
    return addColumn(ColumnBuilder(columnName, dataType).primaryKey());
  }

  /// Convenience method to add an auto-incrementing integer primary key
  TableBuilder autoIncrementPrimaryKey(String columnName) {
    return addColumn(ColumnBuilder(columnName, SqliteDataType.integer).primaryKey());
  }

  /// Generates the SQL CREATE TABLE statement
  String toSql() {
    if (columns.isEmpty) {
      throw StateError('Table "$name" must have at least one column');
    }
    
    final buffer = StringBuffer();
    buffer.write('CREATE TABLE $name (\n');
    
    // Add column definitions
    for (int i = 0; i < columns.length; i++) {
      buffer.write('  ${columns[i].toSql()}');
      if (i < columns.length - 1) {
        buffer.write(',');
      }
      buffer.write('\n');
    }
    
    buffer.write(')');
    return buffer.toString();
  }

  /// Generates SQL statements for all indices on this table
  List<String> indexSqlStatements() {
    return indices.map((index) => index.toSql()).toList();
  }

  /// Generates all SQL statements needed to create this table and its indices
  List<String> allSqlStatements() {
    return [toSql(), ...indexSqlStatements()];
  }

  @override
  String toString() => toSql();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableBuilder &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          _listEquals(columns, other.columns) &&
          _listEquals(indices, other.indices);

  @override
  int get hashCode =>
      name.hashCode ^
      columns.hashCode ^
      indices.hashCode;

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}