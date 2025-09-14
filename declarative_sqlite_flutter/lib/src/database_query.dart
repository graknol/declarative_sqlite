import 'package:flutter/foundation.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// A value-comparable database query specification that supports hot swapping.
/// 
/// This class represents a complete database query that can be compared by value
/// rather than reference, enabling reactive widgets to properly unsubscribe/subscribe
/// when query parameters change.
@immutable
class DatabaseQuery {
  /// Table name to query
  final String tableName;
  
  /// Optional WHERE clause
  final String? where;
  
  /// Optional WHERE clause arguments
  final List<dynamic>? whereArgs;
  
  /// Optional ORDER BY clause
  final String? orderBy;
  
  /// Optional LIMIT clause
  final int? limit;
  
  /// Optional OFFSET clause
  final int? offset;
  
  /// Columns to select (null means SELECT *)
  final List<String>? columns;
  
  /// Whether this is a single record query (getByPrimaryKey)
  final bool isSingleRecord;
  
  /// Primary key value for single record queries
  final dynamic primaryKey;
  
  /// Primary key column name for single record queries
  final String primaryKeyColumn;

  const DatabaseQuery({
    required this.tableName,
    this.where,
    this.whereArgs,
    this.orderBy,
    this.limit,
    this.offset,
    this.columns,
    this.isSingleRecord = false,
    this.primaryKey,
    this.primaryKeyColumn = 'id',
  });

  /// Create a query for a single record by primary key
  factory DatabaseQuery.byPrimaryKey(
    String tableName,
    dynamic primaryKey, {
    String primaryKeyColumn = 'id',
    List<String>? columns,
  }) {
    return DatabaseQuery(
      tableName: tableName,
      isSingleRecord: true,
      primaryKey: primaryKey,
      primaryKeyColumn: primaryKeyColumn,
      columns: columns,
    );
  }

  /// Create a query for multiple records with filtering
  factory DatabaseQuery.where(
    String tableName, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
    List<String>? columns,
  }) {
    return DatabaseQuery(
      tableName: tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      columns: columns,
      isSingleRecord: false,
    );
  }

  /// Create a query for all records in a table
  factory DatabaseQuery.all(
    String tableName, {
    String? orderBy,
    int? limit,
    int? offset,
    List<String>? columns,
  }) {
    return DatabaseQuery(
      tableName: tableName,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      columns: columns,
      isSingleRecord: false,
    );
  }

  /// Execute this query and return a single record (or null)
  Future<Map<String, dynamic>?> executeSingle(DataAccess dataAccess) async {
    if (isSingleRecord) {
      return await dataAccess.getByPrimaryKey(tableName, primaryKey);
    }
    
    final results = await dataAccess.getAllWhere(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: 1,
      columns: columns,
    );
    
    return results.isNotEmpty ? results.first : null;
  }

  /// Execute this query and return a list of records
  Future<List<Map<String, dynamic>>> executeMany(DataAccess dataAccess) async {
    if (isSingleRecord) {
      final record = await dataAccess.getByPrimaryKey(tableName, primaryKey);
      return record != null ? [record] : [];
    }
    
    return await dataAccess.getAllWhere(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      columns: columns,
    );
  }

  /// Create a copy of this query with updated parameters
  DatabaseQuery copyWith({
    String? tableName,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
    List<String>? columns,
    bool? isSingleRecord,
    dynamic primaryKey,
    String? primaryKeyColumn,
  }) {
    return DatabaseQuery(
      tableName: tableName ?? this.tableName,
      where: where ?? this.where,
      whereArgs: whereArgs ?? this.whereArgs,
      orderBy: orderBy ?? this.orderBy,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      columns: columns ?? this.columns,
      isSingleRecord: isSingleRecord ?? this.isSingleRecord,
      primaryKey: primaryKey ?? this.primaryKey,
      primaryKeyColumn: primaryKeyColumn ?? this.primaryKeyColumn,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is DatabaseQuery &&
        tableName == other.tableName &&
        where == other.where &&
        _listEquals(whereArgs, other.whereArgs) &&
        orderBy == other.orderBy &&
        limit == other.limit &&
        offset == other.offset &&
        _listEquals(columns, other.columns) &&
        isSingleRecord == other.isSingleRecord &&
        primaryKey == other.primaryKey &&
        primaryKeyColumn == other.primaryKeyColumn;
  }

  /// Helper method to compare lists for equality
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    return Object.hash(
      tableName,
      where,
      whereArgs,
      orderBy,
      limit,
      offset,
      columns,
      isSingleRecord,
      primaryKey,
      primaryKeyColumn,
    );
  }

  @override
  String toString() {
    if (isSingleRecord) {
      return 'DatabaseQuery.byPrimaryKey($tableName, $primaryKey)';
    }
    
    final parts = <String>['SELECT'];
    
    if (columns != null) {
      parts.add(columns!.join(', '));
    } else {
      parts.add('*');
    }
    
    parts.add('FROM $tableName');
    
    if (where != null) {
      parts.add('WHERE $where');
    }
    
    if (orderBy != null) {
      parts.add('ORDER BY $orderBy');
    }
    
    if (limit != null) {
      parts.add('LIMIT $limit');
    }
    
    if (offset != null) {
      parts.add('OFFSET $offset');
    }
    
    return parts.join(' ');
  }
}

/// A builder class for creating complex database queries with faceted search capabilities.
/// 
/// This builder supports creating queries that can be compared by value and used
/// for hot swapping in reactive widgets.
class DatabaseQueryBuilder {
  String? _tableName;
  final List<String> _whereConditions = [];
  final List<dynamic> _whereArgs = [];
  final List<String> _orderByColumns = [];
  int? _limit;
  int? _offset;
  List<String>? _columns;

  /// Set the table name
  DatabaseQueryBuilder table(String tableName) {
    _tableName = tableName;
    return this;
  }

  /// Add a WHERE condition
  DatabaseQueryBuilder where(String condition, [List<dynamic>? args]) {
    _whereConditions.add(condition);
    if (args != null) {
      _whereArgs.addAll(args);
    }
    return this;
  }

  /// Add an equals condition
  DatabaseQueryBuilder whereEquals(String column, dynamic value) {
    _whereConditions.add('$column = ?');
    _whereArgs.add(value);
    return this;
  }

  /// Add a LIKE condition for text search
  DatabaseQueryBuilder whereLike(String column, String pattern) {
    _whereConditions.add('$column LIKE ?');
    _whereArgs.add(pattern);
    return this;
  }

  /// Add an IN condition for multiple values
  DatabaseQueryBuilder whereIn(String column, List<dynamic> values) {
    if (values.isNotEmpty) {
      final placeholders = List.filled(values.length, '?').join(', ');
      _whereConditions.add('$column IN ($placeholders)');
      _whereArgs.addAll(values);
    }
    return this;
  }

  /// Add a date range condition
  DatabaseQueryBuilder whereDateRange(String column, DateTime? start, DateTime? end) {
    if (start != null) {
      _whereConditions.add('$column >= ?');
      _whereArgs.add(start.toIso8601String());
    }
    
    if (end != null) {
      _whereConditions.add('$column <= ?');
      _whereArgs.add(end.toIso8601String());
    }
    
    return this;
  }

  /// Add a numeric range condition
  DatabaseQueryBuilder whereRange(String column, num? min, num? max) {
    if (min != null) {
      _whereConditions.add('$column >= ?');
      _whereArgs.add(min);
    }
    
    if (max != null) {
      _whereConditions.add('$column <= ?');
      _whereArgs.add(max);
    }
    
    return this;
  }

  /// Add an OR group of conditions
  DatabaseQueryBuilder whereOr(List<String> conditions, [List<dynamic>? args]) {
    if (conditions.isNotEmpty) {
      _whereConditions.add('(${conditions.join(' OR ')})');
      if (args != null) {
        _whereArgs.addAll(args);
      }
    }
    return this;
  }

  /// Add an ORDER BY column
  DatabaseQueryBuilder orderBy(String column, {bool descending = false}) {
    _orderByColumns.add(descending ? '$column DESC' : '$column ASC');
    return this;
  }

  /// Set the LIMIT
  DatabaseQueryBuilder limit(int limit) {
    _limit = limit;
    return this;
  }

  /// Set the OFFSET
  DatabaseQueryBuilder offset(int offset) {
    _offset = offset;
    return this;
  }

  /// Select specific columns
  DatabaseQueryBuilder select(List<String> columns) {
    _columns = columns;
    return this;
  }

  /// Build the DatabaseQuery
  DatabaseQuery build() {
    if (_tableName == null) {
      throw ArgumentError('Table name is required');
    }

    return DatabaseQuery(
      tableName: _tableName!,
      where: _whereConditions.isNotEmpty ? _whereConditions.join(' AND ') : null,
      whereArgs: _whereArgs.isNotEmpty ? _whereArgs : null,
      orderBy: _orderByColumns.isNotEmpty ? _orderByColumns.join(', ') : null,
      limit: _limit,
      offset: _offset,
      columns: _columns,
    );
  }

  /// Create a builder for faceted search with text search capability
  static DatabaseQueryBuilder facetedSearch(String tableName) {
    return DatabaseQueryBuilder().table(tableName);
  }

  /// Add a free text search across multiple columns
  DatabaseQueryBuilder freeTextSearch(String searchText, List<String> searchColumns) {
    if (searchText.isNotEmpty && searchColumns.isNotEmpty) {
      final conditions = searchColumns.map((col) => '$col LIKE ?').toList();
      final args = searchColumns.map((_) => '%$searchText%').toList();
      
      whereOr(conditions, args);
    }
    return this;
  }
}