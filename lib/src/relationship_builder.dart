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
/// Relationships are identified by their table pair rather than requiring explicit names.
@immutable
class RelationshipBuilder {
  const RelationshipBuilder._({
    required this.parentTable,
    required this.childTable,
    required this.parentColumns,
    required this.childColumns,
    required this.type,
    required this.onDelete,
    this.junctionTable,
    this.junctionParentColumns,
    this.junctionChildColumns,
  });

  /// Creates a one-to-many relationship between two tables
  /// 
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table
  /// [parentColumns] Columns in parent table that act as the primary key
  /// [childColumns] Columns in child table that reference the parent
  /// [onDelete] Action to take when parent record is deleted
  const RelationshipBuilder.oneToMany({
    required String parentTable,
    required String childTable,
    required List<String> parentColumns,
    required List<String> childColumns,
    CascadeAction onDelete = CascadeAction.cascade,
  }) : this._(
    parentTable: parentTable,
    childTable: childTable,
    parentColumns: parentColumns,
    childColumns: childColumns,
    type: RelationshipType.oneToMany,
    onDelete: onDelete,
    junctionTable: null,
    junctionParentColumns: null,
    junctionChildColumns: null,
  );

  /// Creates a many-to-many relationship between two tables using a junction table
  /// 
  /// [parentTable] Name of the first table in the relationship
  /// [childTable] Name of the second table in the relationship
  /// [junctionTable] Name of the junction/linking table
  /// [parentColumns] Columns in parent table that act as the primary key
  /// [childColumns] Columns in child table that act as the primary key
  /// [junctionParentColumns] Columns in junction table referencing parent
  /// [junctionChildColumns] Columns in junction table referencing child
  /// [onDelete] Action to take when parent record is deleted
  const RelationshipBuilder.manyToMany({
    required String parentTable,
    required String childTable,
    required String junctionTable,
    required List<String> parentColumns,
    required List<String> childColumns,
    required List<String> junctionParentColumns,
    required List<String> junctionChildColumns,
    CascadeAction onDelete = CascadeAction.cascade,
  }) : this._(
    parentTable: parentTable,
    childTable: childTable,
    parentColumns: parentColumns,
    childColumns: childColumns,
    type: RelationshipType.manyToMany,
    onDelete: onDelete,
    junctionTable: junctionTable,
    junctionParentColumns: junctionParentColumns,
    junctionChildColumns: junctionChildColumns,
  );



  /// Creates a unique identifier for this relationship based on table names and type
  String get relationshipId {
    switch (type) {
      case RelationshipType.oneToMany:
        return '${parentTable}_to_${childTable}_oneToMany';
      case RelationshipType.manyToMany:
        return '${parentTable}_to_${childTable}_manyToMany_via_${junctionTable}';
    }
  }

  /// Name of the parent table
  final String parentTable;

  /// Name of the child table
  final String childTable;

  /// Column names in the parent table (typically primary key)
  final List<String> parentColumns;

  /// Column names in the child table (foreign key reference)
  final List<String> childColumns;

  /// Type of relationship
  final RelationshipType type;

  /// What to do when parent record is deleted
  final CascadeAction onDelete;

  /// Junction table name (for many-to-many relationships)
  final String? junctionTable;

  /// Junction table columns referencing parent (for many-to-many relationships)
  final List<String>? junctionParentColumns;

  /// Junction table columns referencing child (for many-to-many relationships)  
  final List<String>? junctionChildColumns;



  /// Checks if this is a one-to-many relationship
  bool get isOneToMany => type == RelationshipType.oneToMany;

  /// Checks if this is a many-to-many relationship
  bool get isManyToMany => type == RelationshipType.manyToMany;

  /// Gets the SQL condition for finding child records given a parent value
  /// 
  /// For one-to-many: "child_column = ?" or "(child_col1 = ? AND child_col2 = ?)" for composite
  /// For many-to-many: Involves junction table joins
  String getChildWhereCondition() {
    switch (type) {
      case RelationshipType.oneToMany:
        if (childColumns.length == 1) {
          return '${childColumns.first} = ?';
        } else {
          return childColumns.map((col) => '$col = ?').join(' AND ');
        }
      case RelationshipType.manyToMany:
        // For many-to-many, we need a subquery or join through junction table
        final junctionParentCols = junctionParentColumns!;
        final junctionChildCols = junctionChildColumns!;
        
        if (junctionParentCols.length == 1) {
          return '${childColumns.first} IN (SELECT ${junctionChildCols.first} FROM $junctionTable WHERE ${junctionParentCols.first} = ?)';
        } else {
          // For composite keys, we need a more complex subquery
          final junctionConditions = junctionParentCols.map((col) => '$col = ?').join(' AND ');
          final childConditions = List.generate(childColumns.length, (i) => '${childColumns[i]} = ${junctionChildCols[i]}').join(' AND ');
          return 'EXISTS (SELECT 1 FROM $junctionTable WHERE $junctionConditions AND $childConditions)';
        }
    }
  }

  /// Gets the SQL condition for finding parent records given a child value
  String getParentWhereCondition() {
    switch (type) {
      case RelationshipType.oneToMany:
        if (parentColumns.length == 1) {
          return '${parentColumns.first} = ?';
        } else {
          return parentColumns.map((col) => '$col = ?').join(' AND ');
        }
      case RelationshipType.manyToMany:
        final junctionParentCols = junctionParentColumns!;
        final junctionChildCols = junctionChildColumns!;
        
        if (junctionChildCols.length == 1) {
          return '${parentColumns.first} IN (SELECT ${junctionParentCols.first} FROM $junctionTable WHERE ${junctionChildCols.first} = ?)';
        } else {
          // For composite keys, we need a more complex subquery
          final junctionConditions = junctionChildCols.map((col) => '$col = ?').join(' AND ');
          final parentConditions = List.generate(parentColumns.length, (i) => '${parentColumns[i]} = ${junctionParentCols[i]}').join(' AND ');
          return 'EXISTS (SELECT 1 FROM $junctionTable WHERE $junctionConditions AND $parentConditions)';
        }
    }
  }

  /// Validates that this relationship is properly configured
  List<String> validate() {
    final errors = <String>[];

    if (parentTable.isEmpty) {
      errors.add('Parent table name cannot be empty');
    }

    if (childTable.isEmpty) {
      errors.add('Child table name cannot be empty');
    }

    if (parentColumns.isEmpty) {
      errors.add('Parent columns cannot be empty');
    }

    if (childColumns.isEmpty) {
      errors.add('Child columns cannot be empty');
    }

    if (parentColumns.length != childColumns.length) {
      errors.add('Number of parent columns (${parentColumns.length}) must match number of child columns (${childColumns.length})');
    }

    if (type == RelationshipType.manyToMany) {
      if (junctionTable == null || junctionTable!.isEmpty) {
        errors.add('Junction table is required for many-to-many relationships');
      }
      if (junctionParentColumns == null || junctionParentColumns!.isEmpty) {
        errors.add('Junction parent columns are required for many-to-many relationships');
      }
      if (junctionChildColumns == null || junctionChildColumns!.isEmpty) {
        errors.add('Junction child columns are required for many-to-many relationships');
      }
      if (junctionParentColumns != null && junctionParentColumns!.length != parentColumns.length) {
        errors.add('Number of junction parent columns (${junctionParentColumns!.length}) must match number of parent columns (${parentColumns.length})');
      }
      if (junctionChildColumns != null && junctionChildColumns!.length != childColumns.length) {
        errors.add('Number of junction child columns (${junctionChildColumns!.length}) must match number of child columns (${childColumns.length})');
      }
    }

    return errors;
  }

  @override
  String toString() {
    switch (type) {
      case RelationshipType.oneToMany:
        return 'RelationshipBuilder.oneToMany($parentTable.${parentColumns.join('+')} -> $childTable.${childColumns.join('+')}, onDelete: $onDelete)';
      case RelationshipType.manyToMany:
        return 'RelationshipBuilder.manyToMany($parentTable.${parentColumns.join('+')} <-> $childTable.${childColumns.join('+')} via $junctionTable, onDelete: $onDelete)';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelationshipBuilder &&
          runtimeType == other.runtimeType &&
          parentTable == other.parentTable &&
          childTable == other.childTable &&
          _listEquals(parentColumns, other.parentColumns) &&
          _listEquals(childColumns, other.childColumns) &&
          type == other.type &&
          onDelete == other.onDelete &&
          junctionTable == other.junctionTable &&
          _listEquals(junctionParentColumns, other.junctionParentColumns) &&
          _listEquals(junctionChildColumns, other.junctionChildColumns);

  /// Helper method for list equality comparison
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      parentTable.hashCode ^
      childTable.hashCode ^
      _listHashCode(parentColumns) ^
      _listHashCode(childColumns) ^
      type.hashCode ^
      onDelete.hashCode ^
      (junctionTable?.hashCode ?? 0) ^
      _listHashCode(junctionParentColumns) ^
      _listHashCode(junctionChildColumns);

  /// Helper method for list hash code generation
  int _listHashCode<T>(List<T>? list) {
    if (list == null) return 0;
    int hash = 0;
    for (final item in list) {
      hash ^= item.hashCode;
    }
    return hash;
  }
}