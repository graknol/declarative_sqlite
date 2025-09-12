import 'dart:async';
import 'package:meta/meta.dart';
import 'schema_builder.dart';
import 'table_builder.dart';
import 'column_builder.dart';
import 'relationship_builder.dart';

/// Represents different types of dependencies that can invalidate a stream
enum DependencyType {
  /// Any change to the table invalidates the dependent stream
  wholeTable,
  /// Only changes to specific columns invalidate the stream
  columnWise,
  /// Only changes matching specific WHERE conditions invalidate the stream
  whereClauseWise,
  /// Changes to related tables through relationships invalidate the stream
  relatedTable,
}

/// Represents a specific change that occurred in the database
@immutable
class DatabaseChange {
  const DatabaseChange({
    required this.tableName,
    required this.operation,
    required this.affectedColumns,
    this.whereCondition,
    this.whereArgs,
    this.primaryKeyValue,
    this.oldValues,
    this.newValues,
  });

  /// The table that was changed
  final String tableName;
  
  /// The type of operation (INSERT, UPDATE, DELETE)
  final DatabaseOperation operation;
  
  /// List of column names that were affected by the change
  final Set<String> affectedColumns;
  
  /// Optional WHERE condition if the change was conditional
  final String? whereCondition;
  
  /// Arguments for the WHERE condition
  final List<dynamic>? whereArgs;
  
  /// Primary key value of the affected record (if applicable)
  final dynamic primaryKeyValue;
  
  /// Old column values (for UPDATE operations)
  final Map<String, dynamic>? oldValues;
  
  /// New column values (for INSERT/UPDATE operations)
  final Map<String, dynamic>? newValues;
}

/// Types of database operations
enum DatabaseOperation {
  insert,
  update,
  delete,
  bulkInsert,
  bulkUpdate,
  bulkDelete,
}

/// Represents a dependency that a stream has on database data
@immutable
class StreamDependency {
  const StreamDependency({
    required this.streamId,
    required this.tableName,
    required this.dependencyType,
    this.dependentColumns,
    this.whereCondition,
    this.whereArgs,
    this.relatedTables,
    this.joinConditions,
  });

  /// Unique identifier for the stream
  final String streamId;
  
  /// Primary table that this dependency is on
  final String tableName;
  
  /// Type of dependency
  final DependencyType dependencyType;
  
  /// Specific columns this dependency cares about (for columnWise dependencies)
  final Set<String>? dependentColumns;
  
  /// WHERE condition this dependency cares about (for whereClauseWise dependencies)
  final String? whereCondition;
  
  /// Arguments for the WHERE condition
  final List<dynamic>? whereArgs;
  
  /// Related tables that can affect this stream (for relatedTable dependencies)
  final Set<String>? relatedTables;
  
  /// Join conditions that link related tables
  final Map<String, String>? joinConditions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamDependency &&
          runtimeType == other.runtimeType &&
          streamId == other.streamId &&
          tableName == other.tableName &&
          dependencyType == other.dependencyType;

  @override
  int get hashCode =>
      streamId.hashCode ^ tableName.hashCode ^ dependencyType.hashCode;
}

/// Analyzes SQL queries and schema to determine dependencies
class DependencyAnalyzer {
  const DependencyAnalyzer(this.schema);
  
  final SchemaBuilder schema;
  
  /// Analyzes a simple SELECT query to extract dependencies
  /// This is a simplified version - in a full implementation, this would parse SQL
  Set<StreamDependency> analyzeQuery(String streamId, String query, {List<dynamic>? args}) {
    final dependencies = <StreamDependency>{};
    
    // Convert query to lowercase for easier parsing
    final lowercaseQuery = query.toLowerCase();
    
    // Extract table names mentioned in FROM and JOIN clauses
    final mentionedTables = _extractTableNames(lowercaseQuery);
    
    // For each mentioned table, determine the type of dependency
    for (final tableName in mentionedTables) {
      final table = schema.getTable(tableName);
      if (table == null) continue;
      
      // Determine dependency type based on query characteristics
      final dependencyType = _determineDependencyType(lowercaseQuery, tableName);
      
      switch (dependencyType) {
        case DependencyType.wholeTable:
          dependencies.add(StreamDependency(
            streamId: streamId,
            tableName: tableName,
            dependencyType: DependencyType.wholeTable,
          ));
          break;
          
        case DependencyType.columnWise:
          final columns = _extractColumnDependencies(lowercaseQuery, tableName, table);
          dependencies.add(StreamDependency(
            streamId: streamId,
            tableName: tableName,
            dependencyType: DependencyType.columnWise,
            dependentColumns: columns,
          ));
          break;
          
        case DependencyType.whereClauseWise:
          final (whereCondition, whereArgs) = _extractWhereClauseDependencies(lowercaseQuery, args);
          dependencies.add(StreamDependency(
            streamId: streamId,
            tableName: tableName,
            dependencyType: DependencyType.whereClauseWise,
            whereCondition: whereCondition,
            whereArgs: whereArgs,
          ));
          break;
          
        case DependencyType.relatedTable:
          final relatedTables = _extractRelatedTables(tableName);
          dependencies.add(StreamDependency(
            streamId: streamId,
            tableName: tableName,
            dependencyType: DependencyType.relatedTable,
            relatedTables: relatedTables,
          ));
          break;
      }
    }
    
    return dependencies;
  }
  
  /// Analyzes a DataAccess method call to determine dependencies
  Set<StreamDependency> analyzeDataAccessCall(
    String streamId,
    String methodName,
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    List<String>? columns,
    String? orderBy,
  }) {
    final dependencies = <StreamDependency>{};
    final table = schema.getTable(tableName);
    if (table == null) return dependencies;
    
    // Determine dependency type based on method and parameters
    if (where != null && where.isNotEmpty) {
      // Has WHERE clause - create where-clause dependency
      dependencies.add(StreamDependency(
        streamId: streamId,
        tableName: tableName,
        dependencyType: DependencyType.whereClauseWise,
        whereCondition: where,
        whereArgs: whereArgs,
      ));
    } else if (columns != null && columns.isNotEmpty) {
      // Specific columns requested - create column-wise dependency
      dependencies.add(StreamDependency(
        streamId: streamId,
        tableName: tableName,
        dependencyType: DependencyType.columnWise,
        dependentColumns: columns.toSet(),
      ));
    } else {
      // No specific filtering - whole table dependency
      dependencies.add(StreamDependency(
        streamId: streamId,
        tableName: tableName,
        dependencyType: DependencyType.wholeTable,
      ));
    }
    
    // Add related table dependencies based on schema relationships
    final relatedTables = _extractRelatedTables(tableName);
    if (relatedTables.isNotEmpty) {
      dependencies.add(StreamDependency(
        streamId: streamId,
        tableName: tableName,
        dependencyType: DependencyType.relatedTable,
        relatedTables: relatedTables,
      ));
    }
    
    return dependencies;
  }
  
  /// Extract table names from SQL query
  Set<String> _extractTableNames(String query) {
    final tables = <String>{};
    
    // Simple regex-based extraction - in a full implementation, use a proper SQL parser
    final fromPattern = RegExp(r'from\s+(\w+)', caseSensitive: false);
    final joinPattern = RegExp(r'join\s+(\w+)', caseSensitive: false);
    
    fromPattern.allMatches(query).forEach((match) {
      tables.add(match.group(1)!);
    });
    
    joinPattern.allMatches(query).forEach((match) {
      tables.add(match.group(1)!);
    });
    
    return tables;
  }
  
  /// Determine the most appropriate dependency type for a query
  DependencyType _determineDependencyType(String query, String tableName) {
    // If query has complex WHERE conditions, use where-clause dependency
    if (query.contains('where') && query.contains(tableName)) {
      return DependencyType.whereClauseWise;
    }
    
    // If query mentions specific columns, use column-wise dependency
    if (query.contains('select') && !query.contains('select *')) {
      return DependencyType.columnWise;
    }
    
    // If query has JOINs, consider related table dependencies
    if (query.contains('join')) {
      return DependencyType.relatedTable;
    }
    
    // Default to whole table dependency
    return DependencyType.wholeTable;
  }
  
  /// Extract column dependencies from query
  Set<String> _extractColumnDependencies(String query, String tableName, TableBuilder table) {
    final columns = <String>{};
    
    // Simple implementation - extract columns mentioned in SELECT clause
    final selectPattern = RegExp(r'select\s+(.*?)\s+from', caseSensitive: false);
    final match = selectPattern.firstMatch(query);
    
    if (match != null) {
      final selectClause = match.group(1)!;
      if (selectClause.trim() == '*') {
        // SELECT * - depend on all columns
        columns.addAll(table.columns.map((col) => col.name));
      } else {
        // Parse specific columns
        final columnNames = selectClause.split(',').map((col) => col.trim()).toList();
        for (final columnName in columnNames) {
          // Remove table prefixes if present
          final cleanColumnName = columnName.contains('.') 
              ? columnName.split('.').last 
              : columnName;
          columns.add(cleanColumnName);
        }
      }
    }
    
    return columns;
  }
  
  /// Extract WHERE clause dependencies
  (String?, List<dynamic>?) _extractWhereClauseDependencies(String query, List<dynamic>? args) {
    // Simple implementation - extract WHERE clause
    final wherePattern = RegExp(r'where\s+(.*?)(?:\s+order\s+by|\s+group\s+by|\s+limit|$)', caseSensitive: false);
    final match = wherePattern.firstMatch(query);
    
    if (match != null) {
      return (match.group(1)!.trim(), args);
    }
    
    return (null, null);
  }
  
  /// Extract related tables through schema relationships
  Set<String> _extractRelatedTables(String tableName) {
    final relatedTables = <String>{};
    
    // Find all relationships where this table is involved
    final relationships = schema.relationships;
    
    for (final relationship in relationships) {
      if (relationship.parentTable == tableName) {
        relatedTables.add(relationship.childTable);
        
        // For many-to-many, also include junction table
        if (relationship.type == RelationshipType.manyToMany && 
            relationship.junctionTable != null) {
          relatedTables.add(relationship.junctionTable!);
        }
      } else if (relationship.childTable == tableName) {
        relatedTables.add(relationship.parentTable);
        
        // For many-to-many, also include junction table
        if (relationship.type == RelationshipType.manyToMany && 
            relationship.junctionTable != null) {
          relatedTables.add(relationship.junctionTable!);
        }
      }
    }
    
    return relatedTables;
  }
}

/// Manages stream dependencies and determines when streams should be invalidated
class StreamDependencyTracker {
  StreamDependencyTracker(this.schema) : _analyzer = DependencyAnalyzer(schema);
  
  final SchemaBuilder schema;
  final DependencyAnalyzer _analyzer;
  
  /// Map of stream ID to its dependencies
  final Map<String, Set<StreamDependency>> _streamDependencies = {};
  
  /// Map of table name to streams that depend on it
  final Map<String, Set<String>> _tableDependents = {};
  
  /// Registers a stream and analyzes its dependencies
  void registerStream(
    String streamId,
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    List<String>? columns,
    String? orderBy,
    String? rawQuery,
    List<dynamic>? rawQueryArgs,
  }) {
    Set<StreamDependency> dependencies;
    
    if (rawQuery != null) {
      // Analyze raw SQL query
      dependencies = _analyzer.analyzeQuery(streamId, rawQuery, args: rawQueryArgs);
    } else {
      // Analyze DataAccess method call
      dependencies = _analyzer.analyzeDataAccessCall(
        streamId,
        'getAllWhere', // Default method name
        tableName,
        where: where,
        whereArgs: whereArgs,
        columns: columns,
        orderBy: orderBy,
      );
    }
    
    // Store dependencies
    _streamDependencies[streamId] = dependencies;
    
    // Update reverse mapping
    for (final dependency in dependencies) {
      _tableDependents
          .putIfAbsent(dependency.tableName, () => <String>{})
          .add(streamId);
          
      // Also add related tables
      if (dependency.relatedTables != null) {
        for (final relatedTable in dependency.relatedTables!) {
          _tableDependents
              .putIfAbsent(relatedTable, () => <String>{})
              .add(streamId);
        }
      }
    }
  }
  
  /// Unregisters a stream and cleans up its dependencies
  void unregisterStream(String streamId) {
    final dependencies = _streamDependencies.remove(streamId);
    if (dependencies == null) return;
    
    // Clean up reverse mapping
    for (final dependency in dependencies) {
      _tableDependents[dependency.tableName]?.remove(streamId);
      if (_tableDependents[dependency.tableName]?.isEmpty == true) {
        _tableDependents.remove(dependency.tableName);
      }
      
      // Clean up related tables
      if (dependency.relatedTables != null) {
        for (final relatedTable in dependency.relatedTables!) {
          _tableDependents[relatedTable]?.remove(streamId);
          if (_tableDependents[relatedTable]?.isEmpty == true) {
            _tableDependents.remove(relatedTable);
          }
        }
      }
    }
  }
  
  /// Determines which streams should be invalidated by a database change
  Set<String> getAffectedStreams(DatabaseChange change) {
    final affectedStreams = <String>{};
    
    // Get all streams that depend on the changed table
    final dependentStreams = _tableDependents[change.tableName] ?? <String>{};
    
    for (final streamId in dependentStreams) {
      final dependencies = _streamDependencies[streamId] ?? <StreamDependency>{};
      
      for (final dependency in dependencies) {
        if (_isDependencyAffected(dependency, change)) {
          affectedStreams.add(streamId);
          break; // One affected dependency is enough to invalidate the stream
        }
      }
    }
    
    return affectedStreams;
  }
  
  /// Checks if a specific dependency is affected by a database change
  bool _isDependencyAffected(StreamDependency dependency, DatabaseChange change) {
    switch (dependency.dependencyType) {
      case DependencyType.wholeTable:
        // Any change to the table affects whole-table dependencies
        return dependency.tableName == change.tableName;
        
      case DependencyType.columnWise:
        // Only affects if the changed columns overlap with dependent columns
        if (dependency.tableName != change.tableName) return false;
        if (dependency.dependentColumns == null) return true;
        
        return dependency.dependentColumns!.intersection(change.affectedColumns).isNotEmpty;
        
      case DependencyType.whereClauseWise:
        // Only affects if the change matches the WHERE clause conditions
        if (dependency.tableName != change.tableName) return false;
        
        return _doesChangeMatchWhereClause(dependency, change);
        
      case DependencyType.relatedTable:
        // Affects if any related table was changed
        if (dependency.tableName == change.tableName) return true;
        if (dependency.relatedTables == null) return false;
        
        return dependency.relatedTables!.contains(change.tableName);
    }
  }
  
  /// Checks if a database change matches a WHERE clause dependency
  bool _doesChangeMatchWhereClause(StreamDependency dependency, DatabaseChange change) {
    // This is a simplified implementation
    // In a full implementation, this would evaluate the WHERE clause against the changed data
    
    if (dependency.whereCondition == null) return true;
    
    // For now, we'll be conservative and assume any change might affect the WHERE clause
    // A more sophisticated implementation would parse the WHERE clause and evaluate it
    return true;
  }
  
  /// Gets all registered stream IDs
  Set<String> get registeredStreams => _streamDependencies.keys.toSet();
  
  /// Gets dependencies for a specific stream
  Set<StreamDependency>? getDependencies(String streamId) {
    return _streamDependencies[streamId];
  }
  
  /// Gets statistics about registered dependencies
  DependencyStats getStats() {
    var totalDependencies = 0;
    var wholeTableCount = 0;
    var columnWiseCount = 0;
    var whereClauseCount = 0;
    var relatedTableCount = 0;
    
    for (final dependencies in _streamDependencies.values) {
      totalDependencies += dependencies.length;
      
      for (final dependency in dependencies) {
        switch (dependency.dependencyType) {
          case DependencyType.wholeTable:
            wholeTableCount++;
            break;
          case DependencyType.columnWise:
            columnWiseCount++;
            break;
          case DependencyType.whereClauseWise:
            whereClauseCount++;
            break;
          case DependencyType.relatedTable:
            relatedTableCount++;
            break;
        }
      }
    }
    
    return DependencyStats(
      totalStreams: _streamDependencies.length,
      totalDependencies: totalDependencies,
      wholeTableDependencies: wholeTableCount,
      columnWiseDependencies: columnWiseCount,
      whereClauseDependencies: whereClauseCount,
      relatedTableDependencies: relatedTableCount,
      totalTables: _tableDependents.length,
    );
  }
}

/// Statistics about registered dependencies
@immutable
class DependencyStats {
  const DependencyStats({
    required this.totalStreams,
    required this.totalDependencies,
    required this.wholeTableDependencies,
    required this.columnWiseDependencies,
    required this.whereClauseDependencies,
    required this.relatedTableDependencies,
    required this.totalTables,
  });
  
  final int totalStreams;
  final int totalDependencies;
  final int wholeTableDependencies;
  final int columnWiseDependencies;
  final int whereClauseDependencies;
  final int relatedTableDependencies;
  final int totalTables;
  
  @override
  String toString() {
    return 'DependencyStats(streams: $totalStreams, dependencies: $totalDependencies, '
           'wholeTable: $wholeTableDependencies, columnWise: $columnWiseDependencies, '
           'whereClause: $whereClauseDependencies, relatedTable: $relatedTableDependencies, '
           'tables: $totalTables)';
  }
}