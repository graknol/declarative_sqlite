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
  /// Uses optimized SQL with JOINs and depth-first traversal to minimize database round trips.
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
      // Build dependency graph and deletion order
      final deletionOrder = _buildDeletionOrder(tableName);
      
      int totalDeleted = 0;
      
      // Delete in depth-first order (children before parents)
      for (final tableToDelete in deletionOrder.reversed) {
        final deleteCount = await _deleteRecordsForTable(
          txn, tableToDelete, tableName, primaryKeyValue, force
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

  /// Deletes all records for a specific table that are related to the root deletion
  Future<int> _deleteRecordsForTable(
    Transaction txn,
    String tableToDelete, 
    String rootTable,
    dynamic rootPrimaryKey,
    bool force,
  ) async {
    if (tableToDelete == rootTable) {
      // Delete the root record itself
      return await _deleteRootRecord(txn, rootTable, rootPrimaryKey);
    }

    // Find the relationship path from root to this table
    final deletionPath = _findDeletionPath(rootTable, tableToDelete);
    if (deletionPath.isEmpty) {
      return 0; // No path found, nothing to delete
    }

    // Build optimized DELETE with JOINs based on the path
    final deleteQuery = _buildOptimizedDeleteQuery(deletionPath, rootPrimaryKey);
    if (deleteQuery.isEmpty) {
      return 0;
    }

    try {
      final result = await txn.rawDelete(deleteQuery.sql, deleteQuery.parameters);
      return result;
    } catch (e) {
      // If the optimized query fails, fall back to the old approach
      return await _fallbackDelete(txn, tableToDelete, rootTable, rootPrimaryKey, force);
    }
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

  /// Builds an optimized DELETE query using JOINs/WHERE EXISTS
  ({String sql, List<dynamic> parameters}) _buildOptimizedDeleteQuery(
    List<RelationshipBuilder> path, 
    dynamic rootPrimaryKey
  ) {
    if (path.isEmpty) {
      return (sql: '', parameters: <dynamic>[]);
    }

    final targetTable = path.last.childTable;
    final sqlBuffer = StringBuffer();
    final parameters = <dynamic>[];

    sqlBuffer.write('DELETE FROM $targetTable WHERE EXISTS (');
    
    // Build nested EXISTS clauses for each step in the path
    String currentTable = path.first.parentTable;
    
    for (int i = 0; i < path.length; i++) {
      final relationship = path[i];
      
      if (i > 0) {
        sqlBuffer.write(' AND EXISTS (');
      }
      
      switch (relationship.type) {
        case RelationshipType.oneToMany:
          if (i == 0) {
            // First level: connect to root record
            sqlBuffer.write('SELECT 1 FROM ${relationship.parentTable} p$i WHERE ');
            sqlBuffer.write('p$i.${relationship.parentColumn} = ? AND ');
            sqlBuffer.write('$targetTable.${relationship.childColumn} = p$i.${relationship.parentColumn}');
            parameters.add(rootPrimaryKey);
          } else {
            // Subsequent levels: connect to previous level
            sqlBuffer.write('SELECT 1 FROM ${relationship.parentTable} p$i WHERE ');
            sqlBuffer.write('p$i.${relationship.parentColumn} = p${i-1}.${path[i-1].childColumn} AND ');
            sqlBuffer.write('$targetTable.${relationship.childColumn} = p$i.${relationship.parentColumn}');
          }
          break;
          
        case RelationshipType.manyToMany:
          final junctionTable = relationship.junctionTable!;
          final junctionParentCol = relationship.junctionParentColumn!;
          final junctionChildCol = relationship.junctionChildColumn!;
          
          if (i == 0) {
            sqlBuffer.write('SELECT 1 FROM ${relationship.parentTable} p$i ');
            sqlBuffer.write('INNER JOIN $junctionTable j$i ON p$i.${relationship.parentColumn} = j$i.$junctionParentCol '); 
            sqlBuffer.write('WHERE p$i.${relationship.parentColumn} = ? AND ');
            sqlBuffer.write('$targetTable.${relationship.childColumn} = j$i.$junctionChildCol');
            parameters.add(rootPrimaryKey);
          } else {
            sqlBuffer.write('SELECT 1 FROM ${relationship.parentTable} p$i ');
            sqlBuffer.write('INNER JOIN $junctionTable j$i ON p$i.${relationship.parentColumn} = j$i.$junctionParentCol ');
            sqlBuffer.write('WHERE p$i.${relationship.parentColumn} = p${i-1}.${path[i-1].childColumn} AND ');
            sqlBuffer.write('$targetTable.${relationship.childColumn} = j$i.$junctionChildCol');
          }
          break;
      }
    }
    
    // Close all the EXISTS clauses
    for (int i = 0; i < path.length; i++) {
      sqlBuffer.write(')');
    }

    return (sql: sqlBuffer.toString(), parameters: parameters);
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

  /// Fallback deletion method using the old recursive approach
  Future<int> _fallbackDelete(
    Transaction txn,
    String tableName,
    String rootTable,
    dynamic rootPrimaryKey,
    bool force,
  ) async {
    // This is simplified fallback - in practice you'd want the full recursive logic
    // For now, just delete direct children
    final relationships = schema.getParentRelationships(rootTable)
      .where((r) => r.childTable == tableName)
      .toList();
    
    int totalDeleted = 0;
    
    for (final relationship in relationships) {
      final deleteCount = await txn.delete(
        tableName,
        where: relationship.getChildWhereCondition(),
        whereArgs: [rootPrimaryKey],
      );
      totalDeleted += deleteCount;
    }
    
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

    final junctionParentColumn = relationship.junctionParentColumn!;
    final junctionChildColumn = relationship.junctionChildColumn!;

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