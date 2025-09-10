import 'package:meta/meta.dart';

/// Enum defining types of relationships between tables
enum RelationshipType {
  /// One-to-many relationship (parent has multiple children)
  oneToMany,
  
  /// Many-to-many relationship (requires junction table)
  manyToMany,
}

/// Enum defining cascade behavior for delete operations
enum CascadeAction {
  /// Delete child records when parent is deleted
  cascade,
  
  /// Prevent deletion of parent if children exist
  restrict,
  
  /// Set child foreign key to null when parent is deleted
  setNull,
}

/// Builder for defining relationships between tables without foreign key constraints.
/// 
/// Uses logical relationships based on column matching rather than database-level
/// foreign keys, allowing for flexible relationship management and custom cascade behavior.
@immutable
class RelationshipBuilder {
  const RelationshipBuilder._({
    required this.name,
    required this.parentTable,
    required this.childTable,
    required this.parentColumn,
    required this.childColumn,
    required this.type,
    required this.onDelete,
    this.junctionTable,
    this.junctionParentColumn,
    this.junctionChildColumn,
  });

  /// Creates a one-to-many relationship between two tables
  /// 
  /// [name] Unique identifier for this relationship
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table
  /// [parentColumn] Column in parent table that acts as the primary key
  /// [childColumn] Column in child table that references the parent
  /// [onDelete] Action to take when parent record is deleted
  const RelationshipBuilder.oneToMany({
    required String name,
    required String parentTable,
    required String childTable,
    required String parentColumn,
    required String childColumn,
    CascadeAction onDelete = CascadeAction.cascade,
  }) : this._(
    name: name,
    parentTable: parentTable,
    childTable: childTable,
    parentColumn: parentColumn,
    childColumn: childColumn,
    type: RelationshipType.oneToMany,
    onDelete: onDelete,
    junctionTable: null,
    junctionParentColumn: null,
    junctionChildColumn: null,
  );

  /// Creates a many-to-many relationship between two tables using a junction table
  /// 
  /// [name] Unique identifier for this relationship
  /// [parentTable] Name of the first table in the relationship
  /// [childTable] Name of the second table in the relationship
  /// [junctionTable] Name of the junction/linking table
  /// [parentColumn] Column in parent table that acts as the primary key
  /// [childColumn] Column in child table that acts as the primary key
  /// [junctionParentColumn] Column in junction table referencing parent
  /// [junctionChildColumn] Column in junction table referencing child
  /// [onDelete] Action to take when parent record is deleted
  const RelationshipBuilder.manyToMany({
    required String name,
    required String parentTable,
    required String childTable,
    required String junctionTable,
    required String parentColumn,
    required String childColumn,
    required String junctionParentColumn,
    required String junctionChildColumn,
    CascadeAction onDelete = CascadeAction.cascade,
  }) : this._(
    name: name,
    parentTable: parentTable,
    childTable: childTable,
    parentColumn: parentColumn,
    childColumn: childColumn,
    type: RelationshipType.manyToMany,
    onDelete: onDelete,
    junctionTable: junctionTable,
    junctionParentColumn: junctionParentColumn,
    junctionChildColumn: junctionChildColumn,
  );

  /// Unique name for this relationship
  final String name;

  /// Name of the parent table
  final String parentTable;

  /// Name of the child table
  final String childTable;

  /// Column name in the parent table (typically primary key)
  final String parentColumn;

  /// Column name in the child table (foreign key reference)
  final String childColumn;

  /// Type of relationship
  final RelationshipType type;

  /// What to do when parent record is deleted
  final CascadeAction onDelete;

  /// Junction table name (for many-to-many relationships)
  final String? junctionTable;

  /// Junction table column referencing parent (for many-to-many relationships)
  final String? junctionParentColumn;

  /// Junction table column referencing child (for many-to-many relationships)  
  final String? junctionChildColumn;

  /// Checks if this is a one-to-many relationship
  bool get isOneToMany => type == RelationshipType.oneToMany;

  /// Checks if this is a many-to-many relationship
  bool get isManyToMany => type == RelationshipType.manyToMany;

  /// Gets the SQL condition for finding child records given a parent value
  /// 
  /// For one-to-many: "child_column = ?"
  /// For many-to-many: Involves junction table joins
  String getChildWhereCondition() {
    switch (type) {
      case RelationshipType.oneToMany:
        return '$childColumn = ?';
      case RelationshipType.manyToMany:
        // For many-to-many, we need a subquery or join through junction table
        return '$childColumn IN (SELECT $junctionChildColumn FROM $junctionTable WHERE $junctionParentColumn = ?)';
    }
  }

  /// Gets the SQL condition for finding parent records given a child value
  String getParentWhereCondition() {
    switch (type) {
      case RelationshipType.oneToMany:
        return '$parentColumn = ?';
      case RelationshipType.manyToMany:
        return '$parentColumn IN (SELECT $junctionParentColumn FROM $junctionTable WHERE $junctionChildColumn = ?)';
    }
  }

  /// Validates that this relationship is properly configured
  List<String> validate() {
    final errors = <String>[];

    if (name.isEmpty) {
      errors.add('Relationship name cannot be empty');
    }

    if (parentTable.isEmpty) {
      errors.add('Parent table name cannot be empty');
    }

    if (childTable.isEmpty) {
      errors.add('Child table name cannot be empty');
    }

    if (parentColumn.isEmpty) {
      errors.add('Parent column name cannot be empty');
    }

    if (childColumn.isEmpty) {
      errors.add('Child column name cannot be empty');
    }

    if (type == RelationshipType.manyToMany) {
      if (junctionTable == null || junctionTable!.isEmpty) {
        errors.add('Junction table is required for many-to-many relationships');
      }
      if (junctionParentColumn == null || junctionParentColumn!.isEmpty) {
        errors.add('Junction parent column is required for many-to-many relationships');
      }
      if (junctionChildColumn == null || junctionChildColumn!.isEmpty) {
        errors.add('Junction child column is required for many-to-many relationships');
      }
    }

    return errors;
  }

  @override
  String toString() {
    switch (type) {
      case RelationshipType.oneToMany:
        return 'RelationshipBuilder.oneToMany(name: $name, $parentTable.$parentColumn -> $childTable.$childColumn, onDelete: $onDelete)';
      case RelationshipType.manyToMany:
        return 'RelationshipBuilder.manyToMany(name: $name, $parentTable.$parentColumn <-> $childTable.$childColumn via $junctionTable, onDelete: $onDelete)';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelationshipBuilder &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          parentTable == other.parentTable &&
          childTable == other.childTable &&
          parentColumn == other.parentColumn &&
          childColumn == other.childColumn &&
          type == other.type &&
          onDelete == other.onDelete &&
          junctionTable == other.junctionTable &&
          junctionParentColumn == other.junctionParentColumn &&
          junctionChildColumn == other.junctionChildColumn;

  @override
  int get hashCode =>
      name.hashCode ^
      parentTable.hashCode ^
      childTable.hashCode ^
      parentColumn.hashCode ^
      childColumn.hashCode ^
      type.hashCode ^
      onDelete.hashCode ^
      (junctionTable?.hashCode ?? 0) ^
      (junctionParentColumn?.hashCode ?? 0) ^
      (junctionChildColumn?.hashCode ?? 0);
}