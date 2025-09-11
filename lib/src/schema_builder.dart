import 'package:meta/meta.dart';
import 'table_builder.dart';
import 'view_builder.dart';
import 'relationship_builder.dart';

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
    required this.relationships,
  });

  /// Creates a new schema builder.
  const SchemaBuilder() : tables = const [], views = const [], relationships = const [];

  /// List of tables in this schema
  final List<TableBuilder> tables;

  /// List of views in this schema
  final List<ViewBuilder> views;

  /// List of relationships in this schema
  final List<RelationshipBuilder> relationships;

  /// Adds a table to this schema
  SchemaBuilder addTable(TableBuilder table) {
    // Check for duplicate table names
    if (tables.any((t) => t.name == table.name)) {
      throw ArgumentError('Table "${table.name}" already exists in schema');
    }
    
    return SchemaBuilder._(
      tables: [...tables, table],
      views: views,
      relationships: relationships,
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
      relationships: relationships,
    );
  }

  /// Creates and adds a new view to this schema using a builder function
  SchemaBuilder view(String viewName, ViewBuilder Function(String) builder) {
    final viewBuilder = builder(viewName);
    return addView(viewBuilder);
  }

  /// Adds a relationship to this schema
  SchemaBuilder addRelationship(RelationshipBuilder relationship) {
    // Check for duplicate relationships (same parent-child-junction combo)
    final existingRelationship = relationships.where((r) => 
      r.parentTable == relationship.parentTable &&
      r.childTable == relationship.childTable &&
      r.type == relationship.type &&
      (r.junctionTable == relationship.junctionTable || (r.junctionTable == null && relationship.junctionTable == null))
    ).firstOrNull;

    if (existingRelationship != null) {
      throw ArgumentError('Relationship between "${relationship.parentTable}" and "${relationship.childTable}" already exists');
    }
    
    // Validate the relationship
    final validationErrors = relationship.validate();
    if (validationErrors.isNotEmpty) {
      throw ArgumentError('Invalid relationship: ${validationErrors.join(', ')}');
    }
    
    // Check that referenced tables exist in the schema
    if (!hasTable(relationship.parentTable)) {
      throw ArgumentError('Relationship references non-existent parent table "${relationship.parentTable}"');
    }
    if (!hasTable(relationship.childTable)) {
      throw ArgumentError('Relationship references non-existent child table "${relationship.childTable}"');
    }
    if (relationship.junctionTable != null && !hasTable(relationship.junctionTable!)) {
      throw ArgumentError('Relationship references non-existent junction table "${relationship.junctionTable}"');
    }
    
    return SchemaBuilder._(
      tables: tables,
      views: views,
      relationships: [...relationships, relationship],
    );
  }

  /// Creates and adds a new one-to-many relationship to this schema
  SchemaBuilder oneToMany(
    String parentTable,
    String childTable, {
    String parentColumn = 'id',
    String? childColumn,
    CascadeAction onDelete = CascadeAction.cascade,
  }) {
    // Use parentTable_id as default child column if not specified
    final actualChildColumn = childColumn ?? '${parentTable.toLowerCase()}_id';
    
    final relationship = RelationshipBuilder.oneToMany(
      parentTable: parentTable,
      childTable: childTable,
      parentColumn: parentColumn,
      childColumn: actualChildColumn,
      onDelete: onDelete,
    );
    
    return addRelationship(relationship);
  }

  /// Creates and adds a new many-to-many relationship to this schema
  SchemaBuilder manyToMany(
    String parentTable,
    String childTable,
    String junctionTable, {
    String parentColumn = 'id',
    String childColumn = 'id',
    String? junctionParentColumn,
    String? junctionChildColumn,
    CascadeAction onDelete = CascadeAction.cascade,
  }) {
    // Use sensible defaults for junction table columns
    final actualJunctionParentColumn = junctionParentColumn ?? '${parentTable.toLowerCase()}_id';
    final actualJunctionChildColumn = junctionChildColumn ?? '${childTable.toLowerCase()}_id';
    
    final relationship = RelationshipBuilder.manyToMany(
      parentTable: parentTable,
      childTable: childTable,
      junctionTable: junctionTable,
      parentColumn: parentColumn,
      childColumn: childColumn,
      junctionParentColumn: actualJunctionParentColumn,
      junctionChildColumn: actualJunctionChildColumn,
      onDelete: onDelete,
    );
    
    return addRelationship(relationship);
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

  /// Gets a relationship by parent and child table names, or null if it doesn't exist
  RelationshipBuilder? getRelationship(String parentTable, String childTable, {String? junctionTable}) {
    return relationships.where((r) => 
      r.parentTable == parentTable && 
      r.childTable == childTable &&
      (junctionTable == null || r.junctionTable == junctionTable)
    ).firstOrNull;
  }

  /// Gets all relationships for a specific table pair (both directions)
  List<RelationshipBuilder> getRelationshipsBetween(String table1, String table2) {
    return relationships.where((r) => 
      (r.parentTable == table1 && r.childTable == table2) ||
      (r.parentTable == table2 && r.childTable == table1)
    ).toList();
  }

  /// Checks if a table exists in this schema
  bool hasTable(String tableName) {
    return tables.any((t) => t.name == tableName);
  }

  /// Checks if a view exists in this schema
  bool hasView(String viewName) {
    return views.any((v) => v.name == viewName);
  }

  /// Checks if a relationship exists between two tables
  bool hasRelationship(String parentTable, String childTable, {String? junctionTable}) {
    return getRelationship(parentTable, childTable, junctionTable: junctionTable) != null;
  }

  /// Gets all relationships where the specified table is a parent
  List<RelationshipBuilder> getParentRelationships(String tableName) {
    return relationships.where((r) => r.parentTable == tableName).toList();
  }

  /// Gets all relationships where the specified table is a child
  List<RelationshipBuilder> getChildRelationships(String tableName) {
    return relationships.where((r) => r.childTable == tableName).toList();
  }

  /// Gets all relationships involving the specified table (as parent or child)
  List<RelationshipBuilder> getTableRelationships(String tableName) {
    return relationships
        .where((r) => r.parentTable == tableName || r.childTable == tableName)
        .toList();
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

  /// Gets all relationship IDs in this schema  
  List<String> get relationshipIds => relationships.map((r) => r.relationshipId).toList();

  /// Gets count of relationships in this schema
  int get relationshipCount => relationships.length;

  /// Gets all relationship names (IDs) in this schema  
  List<String> get relationshipNames => relationships.map((r) => r.relationshipId).toList();

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
    if (relationships.isNotEmpty) {
      parts.add('relationships: [${relationshipNames.join(', ')}]');
    }
    return 'SchemaBuilder(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SchemaBuilder &&
          runtimeType == other.runtimeType &&
          _listEquals(tables, other.tables) &&
          _listEquals(views, other.views) &&
          _listEquals(relationships, other.relationships);

  @override
  int get hashCode => tables.hashCode ^ views.hashCode ^ relationships.hashCode;

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}