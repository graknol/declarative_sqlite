import 'package:meta/meta.dart';
import 'table_builder.dart';
import 'view_builder.dart';

/// Main entry point for building database schemas declaratively.
/// 
/// Provides a fluent interface for defining database schemas with tables,
/// views, columns, indices, and constraints. Can be executed against a SQLite
/// database to create or update the schema.
@immutable
class SchemaBuilder {
  const SchemaBuilder._({
    required this.tables,
    required this.views,
  });

  /// Creates a new schema builder.
  const SchemaBuilder() : tables = const [], views = const [];

  /// List of tables in this schema
  final List<TableBuilder> tables;

  /// List of views in this schema
  final List<ViewBuilder> views;

  /// Adds a table to this schema
  SchemaBuilder addTable(TableBuilder table) {
    // Check for duplicate table names
    if (tables.any((t) => t.name == table.name)) {
      throw ArgumentError('Table "${table.name}" already exists in schema');
    }
    
    return SchemaBuilder._(
      tables: [...tables, table],
      views: views,
    );
  }

  /// Creates and adds a new table to this schema using a builder function
  SchemaBuilder table(String tableName, TableBuilder Function(TableBuilder) builder) {
    final tableBuilder = builder(TableBuilder(tableName));
    return addTable(tableBuilder);
  }

  /// Adds a view to this schema
  SchemaBuilder addView(ViewBuilder view) {
    // Check for duplicate view names
    if (views.any((v) => v.name == view.name)) {
      throw ArgumentError('View "${view.name}" already exists in schema');
    }
    // Also check for name conflicts with tables
    if (tables.any((t) => t.name == view.name)) {
      throw ArgumentError('View "${view.name}" conflicts with existing table name');
    }
    
    return SchemaBuilder._(
      tables: tables,
      views: [...views, view],
    );
  }

  /// Creates and adds a new view to this schema using a builder function
  SchemaBuilder view(String viewName, ViewBuilder Function(String) builder) {
    final viewBuilder = builder(viewName);
    return addView(viewBuilder);
  }

  /// Gets a table by name, or null if it doesn't exist
  TableBuilder? getTable(String tableName) {
    try {
      return tables.firstWhere((t) => t.name == tableName);
    } catch (e) {
      return null;
    }
  }

  /// Gets a view by name, or null if it doesn't exist
  ViewBuilder? getView(String viewName) {
    try {
      return views.firstWhere((v) => v.name == viewName);
    } catch (e) {
      return null;
    }
  }

  /// Checks if a table exists in this schema
  bool hasTable(String tableName) {
    return tables.any((t) => t.name == tableName);
  }

  /// Checks if a view exists in this schema
  bool hasView(String viewName) {
    return views.any((v) => v.name == viewName);
  }

  /// Generates all SQL statements needed to create this schema
  List<String> toSqlStatements() {
    final statements = <String>[];
    
    // Add table statements first (views may depend on tables)
    for (final table in tables) {
      statements.addAll(table.allSqlStatements());
    }
    
    // Add view statements
    for (final view in views) {
      statements.add(view.toSql());
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

  /// Gets all view names in this schema
  List<String> get viewNames => views.map((v) => v.name).toList();

  /// Gets all object names (tables and views) in this schema
  List<String> get allNames => [...tableNames, ...viewNames];

  /// Returns the number of tables in this schema
  int get tableCount => tables.length;

  /// Returns the number of views in this schema
  int get viewCount => views.length;

  /// Returns the total number of objects (tables and views) in this schema
  int get totalCount => tableCount + viewCount;

  /// Checks if the schema is empty (has no tables or views)
  bool get isEmpty => tables.isEmpty && views.isEmpty;

  /// Checks if the schema has tables or views
  bool get isNotEmpty => tables.isNotEmpty || views.isNotEmpty;

  @override
  String toString() {
    if (isEmpty) {
      return 'SchemaBuilder(empty)';
    }
    final parts = <String>[];
    if (tables.isNotEmpty) {
      parts.add('tables: [${tableNames.join(', ')}]');
    }
    if (views.isNotEmpty) {
      parts.add('views: [${viewNames.join(', ')}]');
    }
    return 'SchemaBuilder(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SchemaBuilder &&
          runtimeType == other.runtimeType &&
          _listEquals(tables, other.tables) &&
          _listEquals(views, other.views);

  @override
  int get hashCode => tables.hashCode ^ views.hashCode;

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}