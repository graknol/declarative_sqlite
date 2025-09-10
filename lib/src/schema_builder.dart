import 'package:meta/meta.dart';
import 'table_builder.dart';

/// Main entry point for building database schemas declaratively.
/// 
/// Provides a fluent interface for defining database schemas with tables,
/// columns, indices, and constraints. Can be executed against a SQLite
/// database to create or update the schema.
@immutable
class SchemaBuilder {
  const SchemaBuilder._({
    required this.tables,
  });

  /// Creates a new schema builder.
  const SchemaBuilder() : tables = const [];

  /// List of tables in this schema
  final List<TableBuilder> tables;

  /// Adds a table to this schema
  SchemaBuilder addTable(TableBuilder table) {
    // Check for duplicate table names
    if (tables.any((t) => t.name == table.name)) {
      throw ArgumentError('Table "${table.name}" already exists in schema');
    }
    
    return SchemaBuilder._(
      tables: [...tables, table],
    );
  }

  /// Creates and adds a new table to this schema using a builder function
  SchemaBuilder table(String tableName, TableBuilder Function(TableBuilder) builder) {
    final tableBuilder = builder(TableBuilder(tableName));
    return addTable(tableBuilder);
  }

  /// Gets a table by name, or null if it doesn't exist
  TableBuilder? getTable(String tableName) {
    try {
      return tables.firstWhere((t) => t.name == tableName);
    } catch (e) {
      return null;
    }
  }

  /// Checks if a table exists in this schema
  bool hasTable(String tableName) {
    return tables.any((t) => t.name == tableName);
  }

  /// Generates all SQL statements needed to create this schema
  List<String> toSqlStatements() {
    final statements = <String>[];
    
    for (final table in tables) {
      statements.addAll(table.allSqlStatements());
    }
    
    return statements;
  }

  /// Generates a single SQL script with all statements separated by semicolons
  String toSqlScript() {
    final statements = toSqlStatements();
    return statements.map((stmt) => '$stmt;').join('\n\n');
  }

  /// Gets all table names in this schema
  List<String> get tableNames => tables.map((t) => t.name).toList();

  /// Returns the number of tables in this schema
  int get tableCount => tables.length;

  /// Checks if the schema is empty (has no tables)
  bool get isEmpty => tables.isEmpty;

  /// Checks if the schema has tables
  bool get isNotEmpty => tables.isNotEmpty;

  @override
  String toString() {
    if (isEmpty) {
      return 'SchemaBuilder(empty)';
    }
    return 'SchemaBuilder(tables: [${tableNames.join(', ')}])';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SchemaBuilder &&
          runtimeType == other.runtimeType &&
          _listEquals(tables, other.tables);

  @override
  int get hashCode => tables.hashCode;

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}