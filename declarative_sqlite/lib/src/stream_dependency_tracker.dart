import 'dart:async';
import 'package:meta/meta.dart';
import 'schema_builder.dart';
import 'table_builder.dart';
import 'column_builder.dart';
import 'relationship_builder.dart';
import 'query_builder.dart';
import 'condition_builder.dart';

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
  
  /// Analyzes a SQL query to extract dependencies
  /// Uses a conservative approach that prioritizes correctness over optimization
  Set<StreamDependency> analyzeQuery(String streamId, String query, {List<dynamic>? args}) {
    final dependencies = <StreamDependency>{};
    
    // Convert query to lowercase for easier parsing
    final lowercaseQuery = query.toLowerCase();
    
    // Extract table names mentioned in FROM and JOIN clauses
    final mentionedTables = _extractTableNames(lowercaseQuery);
    
    // For complex queries (JOINs, subqueries, CTEs), use whole-table dependencies for reliability
    final isComplexQuery = _isComplexQuery(lowercaseQuery);
    
    if (isComplexQuery) {
      // Use whole-table dependencies for all mentioned tables to ensure correctness
      for (final tableName in mentionedTables) {
        final table = schema.getTable(tableName);
        if (table == null) continue;
        
        dependencies.add(StreamDependency(
          streamId: streamId,
          tableName: tableName,
          dependencyType: DependencyType.wholeTable,
        ));
      }
    } else {
      // For simple queries, try to optimize with more specific dependencies
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
  
  /// Analyzes a QueryBuilder to determine dependencies using metadata
  /// This is the preferred method as it uses metadata instead of SQL parsing
  Set<StreamDependency> analyzeQueryBuilder(String streamId, QueryBuilder queryBuilder) {
    final dependencies = <StreamDependency>{};
    
    // Get the main table from the FROM clause
    final mainTableName = queryBuilder.fromTable;
    if (mainTableName == null) {
      return dependencies; // No table to analyze
    }
    
    final mainTable = schema.getTable(mainTableName);
    if (mainTable == null) return dependencies;
    
    // Get all referenced tables (main table + joined tables)
    final allTables = <String>{mainTableName};
    for (final join in queryBuilder.joins) {
      allTables.add(join.tableName);
    }
    
    // Determine dependency type based on query complexity
    final hasJoins = queryBuilder.joins.isNotEmpty;
    final hasWhereCondition = queryBuilder.whereConditionBuilder != null;
    final hasSpecificColumns = queryBuilder.selectExpressions.any((expr) => 
      !expr.toSql().contains('*') && _isColumnExpression(expr.toSql())
    );
    
    if (hasJoins) {
      // Complex query with joins - use whole-table dependencies for all tables
      for (final tableName in allTables) {
        dependencies.add(StreamDependency(
          streamId: streamId,
          tableName: tableName,
          dependencyType: DependencyType.wholeTable,
        ));
      }
    } else if (hasWhereCondition) {
      // Simple query with WHERE clause - analyze the condition builder for precise dependencies
      final whereBuilder = queryBuilder.whereConditionBuilder!;
      final whereColumns = _extractColumnsFromConditionBuilder(whereBuilder);
      
      dependencies.add(StreamDependency(
        streamId: streamId,
        tableName: mainTableName,
        dependencyType: DependencyType.whereClauseWise,
        whereCondition: whereBuilder.toSql(),
        whereArgs: whereBuilder.getArguments(),
        dependentColumns: whereColumns,
      ));
    } else if (hasSpecificColumns) {
      // Query with specific columns - use column-wise dependency
      final dependentColumns = <String>{};
      for (final expr in queryBuilder.selectExpressions) {
        if (_isColumnExpression(expr.toSql())) {
          final columnName = _extractColumnNameFromExpression(expr.toSql());
          if (columnName != null) {
            dependentColumns.add(columnName);
          }
        }
      }
      
      // Also include columns from WHERE, GROUP BY, ORDER BY
      if (queryBuilder.whereConditionBuilder != null) {
        final whereColumns = _extractColumnsFromConditionBuilder(queryBuilder.whereConditionBuilder!);
        dependentColumns.addAll(whereColumns);
      }
      
      dependentColumns.addAll(queryBuilder.groupByColumns);
      
      for (final orderSpec in queryBuilder.orderByColumns) {
        final columnName = _extractColumnNameFromOrderSpec(orderSpec);
        if (columnName != null) {
          dependentColumns.add(columnName);
        }
      }
      
      dependencies.add(StreamDependency(
        streamId: streamId,
        tableName: mainTableName,
        dependencyType: DependencyType.columnWise,
        dependentColumns: dependentColumns,
      ));
    } else {
      // Simple query without specific filters - whole table dependency
      dependencies.add(StreamDependency(
        streamId: streamId,
        tableName: mainTableName,
        dependencyType: DependencyType.wholeTable,
      ));
    }
    
    // Add related table dependencies based on schema relationships
    final relatedTables = _extractRelatedTables(mainTableName);
    if (relatedTables.isNotEmpty) {
      dependencies.add(StreamDependency(
        streamId: streamId,
        tableName: mainTableName,
        dependencyType: DependencyType.relatedTable,
        relatedTables: relatedTables,
      ));
    }
    
    return dependencies;
  }
  
  /// Checks if a query is complex and requires conservative dependency tracking
  bool _isComplexQuery(String query) {
    return query.contains('join') ||
           query.contains('union') ||
           query.contains('with') ||  // CTE
           query.contains('exists') ||
           query.contains('select') && query.split('select').length > 2 ||  // Subqueries
           query.contains('window') ||
           query.contains('over(') ||
           query.contains('case when');
  }

  /// Extract table names from SQL query using improved patterns
  Set<String> _extractTableNames(String query) {
    final tables = <String>{};
    
    // Improved regex patterns for better table extraction
    final patterns = [
      RegExp(r'from\s+(\w+)', caseSensitive: false),
      RegExp(r'join\s+(\w+)', caseSensitive: false),
      RegExp(r'update\s+(\w+)', caseSensitive: false),
      RegExp(r'insert\s+into\s+(\w+)', caseSensitive: false),
      RegExp(r'delete\s+from\s+(\w+)', caseSensitive: false),
    ];
    
    for (final pattern in patterns) {
      pattern.allMatches(query).forEach((match) {
        final tableName = match.group(1)!;
        if (schema.getTable(tableName) != null) {
          tables.add(tableName);
        }
      });
    }
    
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
  
  /// Extracts column name from an expression SQL string
  String? _extractColumnNameFromExpression(String expressionSql) {
    // Remove table prefixes and aliases
    final parts = expressionSql.split(' ');
    final columnPart = parts[0]; // Get the first part before any alias
    
    if (columnPart.contains('.')) {
      // Has table prefix like "table.column"
      return columnPart.split('.').last;
    }
    
    return columnPart == '*' ? null : columnPart;
  }
  
  /// Extracts column names from a WHERE condition string
  Set<String> _extractColumnsFromCondition(String condition) {
    final columns = <String>{};
    
    // Simple regex to find column references (letters/underscore/digits)
    final columnPattern = RegExp(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\b');
    final matches = columnPattern.allMatches(condition);
    
    for (final match in matches) {
      final columnName = match.group(1);
      if (columnName != null && !_isSqlKeyword(columnName)) {
        columns.add(columnName);
      }
    }
    
    return columns;
  }
  
  /// Extracts column name from ORDER BY specification
  String? _extractColumnNameFromOrderSpec(String orderSpec) {
    final parts = orderSpec.trim().split(' ');
    final columnPart = parts[0];
    
    if (columnPart.contains('.')) {
      return columnPart.split('.').last;
    }
    
    return columnPart;
  }
  
  /// Checks if a string is a SQL keyword to avoid false column matches
  bool _isSqlKeyword(String word) {
    final keywords = {
      'select', 'from', 'where', 'and', 'or', 'not', 'in', 'like', 'between',
      'is', 'null', 'true', 'false', 'case', 'when', 'then', 'else', 'end',
      'join', 'inner', 'left', 'right', 'outer', 'on', 'group', 'by', 'order',
      'having', 'limit', 'offset', 'distinct', 'as', 'exists', 'all', 'any',
    };
    return keywords.contains(word.toLowerCase());
  }
  
  /// Determines if an expression represents a column reference
  bool _isColumnExpression(String expressionSql) {
    final sql = expressionSql.toLowerCase().trim();
    
    // Contains function calls
    if (sql.contains('(') && sql.contains(')')) return false;
    
    // Contains mathematical operations
    if (sql.contains('+') || sql.contains('-') || sql.contains('*') || sql.contains('/')) return false;
    
    // Contains string literals
    if (sql.contains("'") || sql.contains('"')) return false;
    
    // Contains SQL keywords that indicate it's not a simple column
    if (sql.contains('case') || sql.contains('when') || sql.contains('then')) return false;
    
    // Check if it looks like a column name (optionally table-qualified)
    final columnPattern = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*\.)?[a-zA-Z_][a-zA-Z0-9_]*$');
    return columnPattern.hasMatch(sql);
  }
  
  /// Extracts column names referenced in a ConditionBuilder
  /// This provides more accurate dependency tracking than string parsing
  Set<String> _extractColumnsFromConditionBuilder(ConditionBuilder conditionBuilder) {
    final columns = <String>{};
    
    // This is a simplified implementation - in a real scenario, you'd want to
    // traverse the condition tree structure to extract all column references
    // For now, we'll extract from the SQL representation
    final sql = conditionBuilder.toSql();
    columns.addAll(_extractColumnsFromCondition(sql));
    
    return columns;
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
  
  /// Registers a stream with QueryBuilder-based dependency analysis
  void registerQueryBuilderStream(String streamId, QueryBuilder queryBuilder) {
    // Analyze dependencies using QueryBuilder metadata
    final dependencies = _analyzer.analyzeQueryBuilder(streamId, queryBuilder);
    
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
    if (dependency.whereCondition == null) return true;
    
    // For INSERT operations, check if the new values would match the WHERE clause
    if (change.operation == DatabaseOperation.insert || 
        change.operation == DatabaseOperation.bulkInsert) {
      if (change.newValues != null) {
        return _evaluateWhereClause(dependency.whereCondition!, dependency.whereArgs, change.newValues!);
      }
    }
    
    // For UPDATE operations, check both old and new values
    if (change.operation == DatabaseOperation.update || 
        change.operation == DatabaseOperation.bulkUpdate) {
      bool oldMatches = false;
      bool newMatches = false;
      
      if (change.oldValues != null) {
        oldMatches = _evaluateWhereClause(dependency.whereCondition!, dependency.whereArgs, change.oldValues!);
      }
      
      if (change.newValues != null) {
        newMatches = _evaluateWhereClause(dependency.whereCondition!, dependency.whereArgs, change.newValues!);
      }
      
      // If either old or new values match, the stream should be updated
      return oldMatches || newMatches;
    }
    
    // For DELETE operations, check if the old values matched the WHERE clause
    if (change.operation == DatabaseOperation.delete || 
        change.operation == DatabaseOperation.bulkDelete) {
      if (change.oldValues != null) {
        return _evaluateWhereClause(dependency.whereCondition!, dependency.whereArgs, change.oldValues!);
      }
    }
    
    // Conservative fallback - trigger the update
    return true;
  }
  
  /// Simple WHERE clause evaluator for basic conditions
  bool _evaluateWhereClause(String whereClause, List<dynamic>? whereArgs, Map<String, dynamic> values) {
    try {
      // Convert WHERE clause to lowercase for easier parsing
      final lowerWhere = whereClause.toLowerCase();
      
      // Handle simple equality checks with hardcoded strings: column = 'value'
      final stringEqualityPattern = RegExp(r"(\w+)\s*=\s*'([^']*)'");
      var match = stringEqualityPattern.firstMatch(lowerWhere);
      if (match != null) {
        final columnName = match.group(1)!;
        final expectedValue = match.group(2)!;
        final actualValue = values[columnName]?.toString();
        return actualValue == expectedValue;
      }
      
      // Handle simple equality checks: column = ?
      final equalityPattern = RegExp(r'(\w+)\s*=\s*\?');
      match = equalityPattern.firstMatch(lowerWhere);
      if (match != null && whereArgs != null && whereArgs.isNotEmpty) {
        final columnName = match.group(1)!;
        final expectedValue = whereArgs[0];
        final actualValue = values[columnName];
        return actualValue == expectedValue;
      }
      
      // Handle simple comparison checks: column > ?, column < ?, etc.
      final comparisonPattern = RegExp(r'(\w+)\s*([><=]+)\s*\?');
      match = comparisonPattern.firstMatch(lowerWhere);
      if (match != null && whereArgs != null && whereArgs.isNotEmpty) {
        final columnName = match.group(1)!;
        final operator = match.group(2)!;
        final expectedValue = whereArgs[0];
        final actualValue = values[columnName];
        
        if (actualValue is num && expectedValue is num) {
          switch (operator) {
            case '>':
              return actualValue > expectedValue;
            case '<':
              return actualValue < expectedValue;
            case '>=':
              return actualValue >= expectedValue;
            case '<=':
              return actualValue <= expectedValue;
            case '=':
              return actualValue == expectedValue;
            case '!=':
            case '<>':
              return actualValue != expectedValue;
          }
        }
      }
      
      // Handle hardcoded numeric comparisons: column > 10, column < 5, etc.
      final hardcodedNumericPattern = RegExp(r'(\w+)\s*([><=!]+)\s*(\d+(?:\.\d+)?)');
      match = hardcodedNumericPattern.firstMatch(lowerWhere);
      if (match != null) {
        final columnName = match.group(1)!;
        final operator = match.group(2)!;
        final expectedValue = double.parse(match.group(3)!);
        final actualValue = values[columnName];
        
        if (actualValue is num) {
          switch (operator) {
            case '>':
              return actualValue > expectedValue;
            case '<':
              return actualValue < expectedValue;
            case '>=':
              return actualValue >= expectedValue;
            case '<=':
              return actualValue <= expectedValue;
            case '=':
              return actualValue == expectedValue;
            case '!=':
            case '<>':
              return actualValue != expectedValue;
          }
        }
      }
      
      // For complex WHERE clauses, be conservative and return true
      return true;
      
    } catch (e) {
      // If evaluation fails, be conservative and return true
      return true;
    }
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