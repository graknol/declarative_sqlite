import 'package:sqflite_common/sqflite.dart';
import 'package:meta/meta.dart';
import 'schema_builder.dart';
import 'table_builder.dart';
import 'relationship_builder.dart';
import 'data_access.dart';

/// Data access layer that provides relationship-aware operations.
/// 
/// Extends the basic DataAccess functionality with support for:
/// - Cascading deletes following relationship definitions
/// - Proxy queries that automatically handle relationship joins
/// - Navigation between related records
class RelatedDataAccess extends DataAccess {
  /// Creates a new RelatedDataAccess instance
  RelatedDataAccess({
    required Database database,
    required SchemaBuilder schema,
  }) : super(database: database, schema: schema);

  /// Gets all child records for a parent record following a specific relationship
  /// 
  /// [relationshipName] Name of the relationship to follow
  /// [parentValue] Value of the parent key (typically the parent record's primary key)
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Optional limit on number of results
  /// 
  /// Returns list of child records as Maps
  Future<List<Map<String, dynamic>>> getRelated(
    String relationshipName,
    dynamic parentValue, {
    String? orderBy,
    int? limit,
  }) async {
    final relationship = schema.getRelationship(relationshipName);
    if (relationship == null) {
      throw ArgumentError('Relationship "$relationshipName" not found in schema');
    }

    switch (relationship.type) {
      case RelationshipType.oneToMany:
        return await _getOneToManyRelated(relationship, parentValue, orderBy: orderBy, limit: limit);
      case RelationshipType.manyToMany:
        return await _getManyToManyRelated(relationship, parentValue, orderBy: orderBy, limit: limit);
    }
  }

  /// Gets all parent records for a child record following a specific relationship
  /// 
  /// [relationshipName] Name of the relationship to follow
  /// [childValue] Value of the child key
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Optional limit on number of results
  /// 
  /// Returns list of parent records as Maps
  Future<List<Map<String, dynamic>>> getRelatedParents(
    String relationshipName,
    dynamic childValue, {
    String? orderBy,
    int? limit,
  }) async {
    final relationship = schema.getRelationship(relationshipName);
    if (relationship == null) {
      throw ArgumentError('Relationship "$relationshipName" not found in schema');
    }

    switch (relationship.type) {
      case RelationshipType.oneToMany:
        // For one-to-many, get the single parent
        final parent = await getAllWhere(
          relationship.parentTable,
          where: relationship.getParentWhereCondition(),
          whereArgs: [childValue],
          orderBy: orderBy,
          limit: limit,
        );
        return parent;
      case RelationshipType.manyToMany:
        return await _getManyToManyParents(relationship, childValue, orderBy: orderBy, limit: limit);
    }
  }

  /// Deletes a record and all its children following relationship cascade rules
  /// 
  /// [tableName] Name of the table containing the parent record
  /// [primaryKeyValue] Primary key value of the record to delete
  /// [force] If true, ignores restrict cascade actions and deletes anyway
  /// 
  /// Returns total number of records deleted across all tables
  Future<int> deleteWithChildren(
    String tableName,
    dynamic primaryKeyValue, {
    bool force = false,
  }) async {
    int totalDeleted = 0;

    return await database.transaction((txn) async {
      totalDeleted += await _deleteWithChildrenRecursive(
        txn, tableName, primaryKeyValue, force, <String>{}
      );
      return totalDeleted;
    });
  }

  /// Recursively deletes a record and its children
  Future<int> _deleteWithChildrenRecursive(
    Transaction txn,
    String tableName,
    dynamic primaryKeyValue,
    bool force,
    Set<String> visitedTables,
  ) async {
    // Prevent infinite recursion in circular relationships
    if (visitedTables.contains(tableName)) {
      return 0;
    }
    visitedTables.add(tableName);

    int totalDeleted = 0;

    // Get all relationships where this table is a parent
    final parentRelationships = schema.getParentRelationships(tableName);

    // Process each child relationship
    for (final relationship in parentRelationships) {
      switch (relationship.onDelete) {
        case CascadeAction.cascade:
          // Get all child records
          final children = await getRelated(relationship.name, primaryKeyValue);
          
          // Recursively delete each child and its descendants
          for (final child in children) {
            final childPrimaryKey = _extractPrimaryKeyValue(relationship.childTable, child);
            if (childPrimaryKey != null) {
              totalDeleted += await _deleteWithChildrenRecursive(
                txn, relationship.childTable, childPrimaryKey, force, Set.from(visitedTables)
              );
            }
          }
          break;

        case CascadeAction.restrict:
          if (!force) {
            // Check if any children exist
            final children = await getRelated(relationship.name, primaryKeyValue);
            if (children.isNotEmpty) {
              throw StateError(
                'Cannot delete record from "$tableName": ${children.length} dependent record(s) exist in "${relationship.childTable}" '
                '(relationship: ${relationship.name}). Use force=true to override.'
              );
            }
          }
          break;

        case CascadeAction.setNull:
          // Set the foreign key column to null for all children
          final childColumn = relationship.childColumn;
          final updateCount = await DataAccess(database: txn, schema: schema).updateWhere(
            relationship.childTable,
            {childColumn: null},
            where: relationship.getChildWhereCondition(),
            whereArgs: [primaryKeyValue],
          );
          // Note: We don't count setNull operations in totalDeleted
          break;
      }
    }

    // Finally delete the parent record itself
    final deleteCount = await DataAccess(database: txn, schema: schema)
        .deleteByPrimaryKey(tableName, primaryKeyValue);
    totalDeleted += deleteCount;

    visitedTables.remove(tableName);
    return totalDeleted;
  }

  /// Gets the primary key value from a record map
  dynamic _extractPrimaryKeyValue(String tableName, Map<String, dynamic> record) {
    final table = schema.getTable(tableName);
    if (table == null) return null;

    final primaryKeys = table.getPrimaryKeyColumns();
    if (primaryKeys.isEmpty) return null;

    if (primaryKeys.length == 1) {
      return record[primaryKeys.first];
    } else {
      // For composite keys, return a map
      final keyMap = <String, dynamic>{};
      for (final keyCol in primaryKeys) {
        keyMap[keyCol] = record[keyCol];
      }
      return keyMap;
    }
  }

  /// Creates a link in a many-to-many relationship
  /// 
  /// [relationshipName] Name of the many-to-many relationship
  /// [parentValue] Value of the parent record's key
  /// [childValue] Value of the child record's key
  Future<void> linkManyToMany(
    String relationshipName,
    dynamic parentValue,
    dynamic childValue,
  ) async {
    final relationship = schema.getRelationship(relationshipName);
    if (relationship == null) {
      throw ArgumentError('Relationship "$relationshipName" not found in schema');
    }

    if (relationship.type != RelationshipType.manyToMany) {
      throw ArgumentError('Relationship "$relationshipName" is not a many-to-many relationship');
    }

    final junctionTable = relationship.junctionTable!;
    final junctionParentColumn = relationship.junctionParentColumn!;
    final junctionChildColumn = relationship.junctionChildColumn!;

    await insert(junctionTable, {
      junctionParentColumn: parentValue,
      junctionChildColumn: childValue,
    });
  }

  /// Removes a link in a many-to-many relationship
  /// 
  /// [relationshipName] Name of the many-to-many relationship
  /// [parentValue] Value of the parent record's key
  /// [childValue] Value of the child record's key
  Future<int> unlinkManyToMany(
    String relationshipName,
    dynamic parentValue,
    dynamic childValue,
  ) async {
    final relationship = schema.getRelationship(relationshipName);
    if (relationship == null) {
      throw ArgumentError('Relationship "$relationshipName" not found in schema');
    }

    if (relationship.type != RelationshipType.manyToMany) {
      throw ArgumentError('Relationship "$relationshipName" is not a many-to-many relationship');
    }

    final junctionTable = relationship.junctionTable!;
    final junctionParentColumn = relationship.junctionParentColumn!;
    final junctionChildColumn = relationship.junctionChildColumn!;

    return await deleteWhere(
      junctionTable,
      where: '$junctionParentColumn = ? AND $junctionChildColumn = ?',
      whereArgs: [parentValue, childValue],
    );
  }

  /// Gets one-to-many related records
  Future<List<Map<String, dynamic>>> _getOneToManyRelated(
    RelationshipBuilder relationship,
    dynamic parentValue, {
    String? orderBy,
    int? limit,
  }) async {
    return await getAllWhere(
      relationship.childTable,
      where: relationship.getChildWhereCondition(),
      whereArgs: [parentValue],
      orderBy: orderBy,
      limit: limit,
    );
  }

  /// Gets many-to-many related records
  Future<List<Map<String, dynamic>>> _getManyToManyRelated(
    RelationshipBuilder relationship,
    dynamic parentValue, {
    String? orderBy,
    int? limit,
  }) async {
    // For many-to-many, we need to join through the junction table
    final junctionTable = relationship.junctionTable!;
    final junctionParentColumn = relationship.junctionParentColumn!;
    final junctionChildColumn = relationship.junctionChildColumn!;
    final childTable = relationship.childTable;
    final childColumn = relationship.childColumn;

    // Build the SQL query with JOIN
    final sql = StringBuffer();
    sql.write('SELECT $childTable.* FROM $childTable ');
    sql.write('INNER JOIN $junctionTable ON $childTable.$childColumn = $junctionTable.$junctionChildColumn ');
    sql.write('WHERE $junctionTable.$junctionParentColumn = ?');
    
    if (orderBy != null) {
      sql.write(' ORDER BY $orderBy');
    }
    if (limit != null) {
      sql.write(' LIMIT $limit');
    }

    final results = await database.rawQuery(sql.toString(), [parentValue]);
    
    // Decode results using table metadata
    final table = schema.getTable(childTable);
    if (table != null) {
      final metadata = getTableMetadata(childTable);
      return results.map((row) => DataTypeUtils.decodeRow(row, metadata.columns)).toList();
    }
    
    return results;
  }

  /// Gets many-to-many parent records
  Future<List<Map<String, dynamic>>> _getManyToManyParents(
    RelationshipBuilder relationship,
    dynamic childValue, {
    String? orderBy,
    int? limit,
  }) async {
    // For many-to-many, we need to join through the junction table
    final junctionTable = relationship.junctionTable!;
    final junctionParentColumn = relationship.junctionParentColumn!;
    final junctionChildColumn = relationship.junctionChildColumn!;
    final parentTable = relationship.parentTable;
    final parentColumn = relationship.parentColumn;

    // Build the SQL query with JOIN
    final sql = StringBuffer();
    sql.write('SELECT $parentTable.* FROM $parentTable ');
    sql.write('INNER JOIN $junctionTable ON $parentTable.$parentColumn = $junctionTable.$junctionParentColumn ');
    sql.write('WHERE $junctionTable.$junctionChildColumn = ?');
    
    if (orderBy != null) {
      sql.write(' ORDER BY $orderBy');
    }
    if (limit != null) {
      sql.write(' LIMIT $limit');
    }

    final results = await database.rawQuery(sql.toString(), [childValue]);
    
    // Decode results using table metadata
    final table = schema.getTable(parentTable);
    if (table != null) {
      final metadata = getTableMetadata(parentTable);
      return results.map((row) => DataTypeUtils.decodeRow(row, metadata.columns)).toList();
    }
    
    return results;
  }
}