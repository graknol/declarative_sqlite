import 'package:sqflite_common/sqflite.dart';
import 'package:meta/meta.dart';
import 'schema_builder.dart';
import 'table_builder.dart';
import 'relationship_builder.dart';
import 'data_access.dart';
import 'data_types.dart';

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

  /// Gets all child records for a parent record following a relationship
  /// 
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table  
  /// [parentValue] Value of the parent key (typically the parent record's primary key)
  /// [junctionTable] Junction table name for many-to-many relationships (optional)
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Optional limit on number of results
  /// 
  /// Returns list of child records as Maps
  Future<List<Map<String, dynamic>>> getRelated(
    String parentTable,
    String childTable,
    dynamic parentValue, {
    String? junctionTable,
    String? orderBy,
    int? limit,
  }) async {
    final relationship = schema.getRelationship(parentTable, childTable, junctionTable: junctionTable);
    if (relationship == null) {
      throw ArgumentError('No relationship found between "$parentTable" and "$childTable"');
    }

    switch (relationship.type) {
      case RelationshipType.oneToMany:
        return await _getOneToManyRelated(relationship, parentValue, orderBy: orderBy, limit: limit);
      case RelationshipType.manyToMany:
        return await _getManyToManyRelated(relationship, parentValue, orderBy: orderBy, limit: limit);
    }
  }

  /// Gets related records following a specific path through multiple tables
  /// 
  /// [path] Array of table names defining the relationship path to follow
  /// [rootValue] Value of the root record's key
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Optional limit on number of results
  /// 
  /// Example: 
  /// - `getRelatedByPath(['users', 'posts', 'comments'], userId)` gets all comments on a user's posts
  /// - `getRelatedByPath(['users', 'comments'], userId)` gets all comments made by a user directly
  /// 
  /// Returns list of target records as Maps
  Future<List<Map<String, dynamic>>> getRelatedByPath(
    List<String> path,
    dynamic rootValue, {
    String? orderBy,
    int? limit,
  }) async {
    if (path.length < 2) {
      throw ArgumentError('Path must contain at least 2 tables');
    }

    final targetTable = path.last;
    
    // Build the relationship path
    final relationshipPath = <RelationshipBuilder>[];
    for (int i = 0; i < path.length - 1; i++) {
      final parentTable = path[i];
      final childTable = path[i + 1];
      
      final relationship = schema.getRelationship(parentTable, childTable);
      if (relationship == null) {
        throw ArgumentError('No relationship found between "$parentTable" and "$childTable" in path');
      }
      
      relationshipPath.add(relationship);
    }

    // Build the nested EXISTS query for path navigation
    final pathQuery = _buildNestedExistsPathQuery(relationshipPath, targetTable, rootValue);
    if (pathQuery.sql.isEmpty) {
      return [];
    }

    var sql = pathQuery.sql;
    if (orderBy != null) {
      sql += ' ORDER BY $orderBy';
    }
    if (limit != null) {
      sql += ' LIMIT $limit';
    }

    final results = await database.rawQuery(sql, pathQuery.parameters);
    
    // Decode results using table metadata
    final table = schema.getTable(targetTable);
    if (table != null) {
      final metadata = getTableMetadata(targetTable);
      return results.map((row) => DataTypeUtils.decodeRow(row, metadata.columns)).toList();
    }
    
    return results;
  }

  /// Gets all parent records for a child record following a relationship
  /// 
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table
  /// [childValue] Value of the child key
  /// [junctionTable] Junction table name for many-to-many relationships (optional)
  /// [orderBy] Optional ORDER BY clause
  /// [limit] Optional limit on number of results
  /// 
  /// Returns list of parent records as Maps
  Future<List<Map<String, dynamic>>> getRelatedParents(
    String parentTable,
    String childTable,
    dynamic childValue, {
    String? junctionTable,
    String? orderBy,
    int? limit,
  }) async {
    final relationship = schema.getRelationship(parentTable, childTable, junctionTable: junctionTable);
    if (relationship == null) {
      throw ArgumentError('No relationship found between "$parentTable" and "$childTable"');
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
  /// Uses optimized SQL with nested WHERE EXISTS and depth-first traversal to minimize database round trips.
  /// Generates O(n) queries where n is the number of tables in hierarchy - one DELETE per table.
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
    return await database.transaction((txn) async {
      // Build dependency graph and deletion order using depth-first traversal
      final deletionOrder = _buildDeletionOrder(tableName);
      
      int totalDeleted = 0;
      
      // Check for restrict cascade violations before doing any deletes
      if (!force) {
        for (final tableToDelete in deletionOrder) {
          if (tableToDelete != tableName) {
            // Check if there are any records to delete with restrict cascade
            final restrictCount = await _countRestrictCascadeViolations(txn, tableName, primaryKeyValue, tableToDelete);
            if (restrictCount > 0) {
              throw StateError('Cannot delete record from "$tableName" because it would violate cascade restrictions in "$tableToDelete"');
            }
          }
        }
      }
      
      // Delete in depth-first order (children before parents)
      for (final tableToDelete in deletionOrder) {
        final deleteCount = await _deleteRecordsWithNestedExists(
          txn, tableToDelete, tableName, primaryKeyValue
        );
        totalDeleted += deleteCount;
      }

      return totalDeleted;
    });
  }

  /// Builds the deletion order for cascading deletes using depth-first traversal
  /// Returns list of table names in the order they should be processed for deletion
  List<String> _buildDeletionOrder(String rootTable) {
    final order = <String>[];
    final visited = <String>{};
    
    void depthFirstTraversal(String tableName) {
      if (visited.contains(tableName)) {
        return; // Prevent infinite recursion
      }
      
      visited.add(tableName);
      
      // Get all child relationships from this table
      final childRelationships = schema.getParentRelationships(tableName);
      
      // Visit all children first (depth-first)
      for (final relationship in childRelationships) {
        if (relationship.onDelete == CascadeAction.cascade || relationship.onDelete == CascadeAction.restrict) {
          depthFirstTraversal(relationship.childTable);
        }
      }
      
      // Add this table to deletion order after processing all children
      if (!order.contains(tableName)) {
        order.add(tableName);
      }
    }
    
    depthFirstTraversal(rootTable);
    return order;
  }

  /// Counts records that would violate restrict cascade rules
  Future<int> _countRestrictCascadeViolations(
    Transaction txn,
    String rootTable,
    dynamic rootPrimaryKey,
    String tableToCheck,
  ) async {
    if (tableToCheck == rootTable) {
      return 0; // Root table is not a violation
    }

    // Find the relationship path from root to this table
    final pathToTable = _findDeletionPath(rootTable, tableToCheck);
    if (pathToTable.isEmpty) {
      return 0; // No relationship path
    }

    // Check if any relationship in the path has restrict cascade
    final hasRestrict = pathToTable.any((r) => r.onDelete == CascadeAction.restrict);
    if (!hasRestrict) {
      return 0; // No restrict cascade in this path
    }

    // Count records that would be affected
    final countQuery = _buildNestedExistsCountQuery(pathToTable, rootPrimaryKey);
    final result = await txn.rawQuery(countQuery.sql, countQuery.parameters);
    return (result.first['count'] as int?) ?? 0;
  }

  /// Deletes records using a nested WHERE EXISTS approach
  Future<int> _deleteRecordsWithNestedExists(
    Transaction txn,
    String tableToDelete,
    String rootTable,
    dynamic rootPrimaryKey,
  ) async {
    if (tableToDelete == rootTable) {
      // Delete the root record itself
      return await _deleteRootRecord(txn, rootTable, rootPrimaryKey);
    }

    // Find the relationship path from root to this table
    final pathToTable = _findDeletionPath(rootTable, tableToDelete);
    if (pathToTable.isEmpty) {
      return 0; // No path found, nothing to delete
    }

    // Build the nested EXISTS DELETE query
    final deleteQuery = _buildNestedExistsDeleteQuery(pathToTable, rootPrimaryKey);
    if (deleteQuery.sql.isEmpty) {
      return 0;
    }

    // Execute the optimized DELETE query
    return await txn.rawDelete(deleteQuery.sql, deleteQuery.parameters);
  }

  /// Builds a COUNT query using nested EXISTS to count affected records
  ({String sql, List<dynamic> parameters}) _buildNestedExistsCountQuery(
    List<RelationshipBuilder> path,
    dynamic rootPrimaryKey,
  ) {
    if (path.isEmpty) {
      return (sql: '', parameters: <dynamic>[]);
    }

    final targetTable = path.last.childTable;
    final parameters = <dynamic>[rootPrimaryKey];

    // Build: SELECT COUNT(*) FROM target_table WHERE EXISTS (nested conditions)
    final sql = 'SELECT COUNT(*) as count FROM $targetTable WHERE ${_buildNestedExistsChain(path, rootPrimaryKey != null)}';
    
    return (sql: sql, parameters: parameters);
  }

  /// Builds a DELETE query using nested EXISTS pattern like user's example
  ({String sql, List<dynamic> parameters}) _buildNestedExistsDeleteQuery(
    List<RelationshipBuilder> path,
    dynamic rootPrimaryKey,
  ) {
    if (path.isEmpty) {
      return (sql: '', parameters: <dynamic>[]);
    }

    final targetTable = path.last.childTable;
    final parameters = <dynamic>[rootPrimaryKey];

    // Start building the DELETE with nested EXISTS
    final buffer = StringBuffer();
    buffer.write('DELETE FROM $targetTable WHERE ');
    
    // Build the nested EXISTS chain from the target table back to the root
    // Each EXISTS clause connects one level to the next
    buffer.write(_buildNestedExistsChain(path, rootPrimaryKey != null));
    
    return (sql: buffer.toString(), parameters: parameters);
  }

  /// Builds a nested EXISTS condition chain
  String _buildNestedExistsChain(List<RelationshipBuilder> path, bool hasRootParameter) {
    if (path.isEmpty) return '';

    final buffer = StringBuffer();
    final targetTable = path.last.childTable;
    
    // Work backwards through the path to build nested EXISTS
    for (int i = path.length - 1; i >= 0; i--) {
      final relationship = path[i];
      final isRoot = (i == 0);
      
      if (i == path.length - 1) {
        // First EXISTS: from target table to its immediate parent
        buffer.write('EXISTS (SELECT 1 FROM ${relationship.parentTable} ');
        
        if (relationship.type == RelationshipType.oneToMany) {
          buffer.write('WHERE ${relationship.parentTable}.${relationship.parentColumns.first} = $targetTable.${relationship.childColumns.first}');
        } else if (relationship.type == RelationshipType.manyToMany) {
          // For many-to-many, join through junction table
          final junctionTable = relationship.junctionTable!;
          final junctionParentCol = relationship.junctionParentColumns!.first; 
          final junctionChildCol = relationship.junctionChildColumns!.first;
          buffer.write('INNER JOIN $junctionTable ON ${relationship.parentTable}.${relationship.parentColumns.first} = $junctionTable.$junctionParentCol ');
          buffer.write('WHERE $junctionTable.$junctionChildCol = $targetTable.${relationship.childColumns.first}');
        }
      } else {
        // Subsequent nested EXISTS - connect this parent to the child from the previous level
        buffer.write(' AND EXISTS (SELECT 1 FROM ${relationship.parentTable} ');
        
        final previousRelationship = path[i + 1]; // Previous level in the chain
        
        if (relationship.type == RelationshipType.oneToMany) {
          // Connect this relationship's parent column to the previous relationship's child column
          // For example: users.id = posts.user_id (where posts.user_id comes from the previous relationship)
          buffer.write('WHERE ${relationship.parentTable}.${relationship.parentColumns.first} = ${previousRelationship.parentTable}.${relationship.childColumns.first}');
        } else if (relationship.type == RelationshipType.manyToMany) {
          final junctionTable = relationship.junctionTable!;
          final junctionParentCol = relationship.junctionParentColumns!.first;
          final junctionChildCol = relationship.junctionChildColumns!.first;
          buffer.write('INNER JOIN $junctionTable ON ${relationship.parentTable}.${relationship.parentColumns.first} = $junctionTable.$junctionParentCol ');
          buffer.write('WHERE $junctionTable.$junctionChildCol = ${previousRelationship.parentTable}.${relationship.childColumns.first}');
        }
      }
      
      // If this is the root level, add the parameter condition
      if (isRoot && hasRootParameter) {
        buffer.write(' AND ${relationship.parentTable}.${relationship.parentColumns.first} = ?');
      }
    }
    
    // Close all the EXISTS parentheses
    for (int i = 0; i < path.length; i++) {
      buffer.write(')');
    }
    
    return buffer.toString();
  }

  /// Builds a SELECT query using nested EXISTS pattern for path navigation
  ({String sql, List<dynamic> parameters}) _buildNestedExistsPathQuery(
    List<RelationshipBuilder> path,
    String targetTable,
    dynamic rootValue,
  ) {
    if (path.isEmpty) {
      return (sql: '', parameters: <dynamic>[]);
    }

    final parameters = <dynamic>[rootValue];
    
    // Build: SELECT * FROM target_table WHERE EXISTS (nested conditions)
    final sql = 'SELECT * FROM $targetTable WHERE ${_buildNestedExistsChain(path, rootValue != null)}';
    
    return (sql: sql, parameters: parameters);
  }

  /// Finds the relationship path from source table to target table
  List<RelationshipBuilder> _findDeletionPath(String sourceTable, String targetTable) {
    final visited = <String>{};
    final path = <RelationshipBuilder>[];
    
    bool findPath(String currentTable, String target, List<RelationshipBuilder> currentPath) {
      if (currentTable == target) {
        path.addAll(currentPath);
        return true;
      }
      
      if (visited.contains(currentTable)) {
        return false;
      }
      
      visited.add(currentTable);
      
      // Try all outgoing relationships
      final childRelationships = schema.getParentRelationships(currentTable);
      
      for (final relationship in childRelationships) {
        if (relationship.onDelete == CascadeAction.cascade || 
            (relationship.onDelete == CascadeAction.restrict)) {
          
          final newPath = [...currentPath, relationship];
          if (findPath(relationship.childTable, target, newPath)) {
            return true;
          }
        }
      }
      
      visited.remove(currentTable);
      return false;
    }
    
    findPath(sourceTable, targetTable, []);
    return path;
  }

  /// Deletes the root record itself
  Future<int> _deleteRootRecord(Transaction txn, String tableName, dynamic primaryKeyValue) async {
    final table = schema.getTable(tableName);
    if (table == null) {
      throw ArgumentError('Table "$tableName" not found in schema');
    }

    final primaryKeyColumns = table.getPrimaryKeyColumns();
    if (primaryKeyColumns.isEmpty) {
      throw ArgumentError('Table "$tableName" has no primary key');
    }

    final (whereClause, whereArgs) = _buildPrimaryKeyWhereClause(primaryKeyColumns, primaryKeyValue);
    
    return await txn.delete(
      tableName,
      where: whereClause,
      whereArgs: whereArgs,
    );
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
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table
  /// [junctionTable] Name of the junction table
  /// [parentValue] Value of the parent record's key
  /// [childValue] Value of the child record's key
  Future<void> linkManyToMany(
    String parentTable,
    String childTable,
    String junctionTable,
    dynamic parentValue,
    dynamic childValue,
  ) async {
    final relationship = schema.getRelationship(parentTable, childTable, junctionTable: junctionTable);
    if (relationship == null) {
      throw ArgumentError('No many-to-many relationship found between "$parentTable" and "$childTable" via "$junctionTable"');
    }

    if (relationship.type != RelationshipType.manyToMany) {
      throw ArgumentError('Relationship between "$parentTable" and "$childTable" is not a many-to-many relationship');
    }

    final junctionParentColumn = relationship.junctionParentColumns!.first;
    final junctionChildColumn = relationship.junctionChildColumns!.first;

    await insert(junctionTable, {
      junctionParentColumn: parentValue,
      junctionChildColumn: childValue,
    });
  }

  /// Removes a link in a many-to-many relationship
  /// 
  /// [parentTable] Name of the parent table
  /// [childTable] Name of the child table
  /// [junctionTable] Name of the junction table
  /// [parentValue] Value of the parent record's key
  /// [childValue] Value of the child record's key
  Future<int> unlinkManyToMany(
    String parentTable,
    String childTable,
    String junctionTable,
    dynamic parentValue,
    dynamic childValue,
  ) async {
    final relationship = schema.getRelationship(parentTable, childTable, junctionTable: junctionTable);
    if (relationship == null) {
      throw ArgumentError('No many-to-many relationship found between "$parentTable" and "$childTable" via "$junctionTable"');
    }

    if (relationship.type != RelationshipType.manyToMany) {
      throw ArgumentError('Relationship between "$parentTable" and "$childTable" is not a many-to-many relationship');
    }

    final junctionParentColumn = relationship.junctionParentColumns!.first;
    final junctionChildColumn = relationship.junctionChildColumns!.first;

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
    final junctionParentColumn = relationship.junctionParentColumns!.first;
    final junctionChildColumn = relationship.junctionChildColumns!.first;
    final childTable = relationship.childTable;
    final childColumn = relationship.childColumns.first;

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
    final junctionParentColumn = relationship.junctionParentColumns!.first;
    final junctionChildColumn = relationship.junctionChildColumns!.first;
    final parentTable = relationship.parentTable;
    final parentColumn = relationship.parentColumns.first;

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

  /// Builds a WHERE clause and arguments for primary key matching
  /// Returns a tuple of (whereClause, whereArgs)
  (String, List<dynamic>) _buildPrimaryKeyWhereClause(List<String> primaryKeyColumns, dynamic primaryKeyValue) {
    if (primaryKeyColumns.length == 1) {
      // Single primary key
      return ('${primaryKeyColumns.first} = ?', [primaryKeyValue]);
    } else {
      // Composite primary key
      if (primaryKeyValue is Map<String, dynamic>) {
        final whereConditions = <String>[];
        final whereArgs = <dynamic>[];
        
        for (final columnName in primaryKeyColumns) {
          if (!primaryKeyValue.containsKey(columnName)) {
            throw ArgumentError('Primary key value map is missing column: $columnName');
          }
          whereConditions.add('$columnName = ?');
          whereArgs.add(primaryKeyValue[columnName]);
        }
        
        return (whereConditions.join(' AND '), whereArgs);
      } else if (primaryKeyValue is List) {
        if (primaryKeyValue.length != primaryKeyColumns.length) {
          throw ArgumentError('Primary key value list length (${primaryKeyValue.length}) does not match number of primary key columns (${primaryKeyColumns.length})');
        }
        
        final whereConditions = <String>[];
        for (int i = 0; i < primaryKeyColumns.length; i++) {
          whereConditions.add('${primaryKeyColumns[i]} = ?');
        }
        
        return (whereConditions.join(' AND '), primaryKeyValue);
      } else {
        throw ArgumentError('Composite primary key requires Map<String, dynamic> or List for primaryKeyValue, got ${primaryKeyValue.runtimeType}');
      }
    }
  }
}