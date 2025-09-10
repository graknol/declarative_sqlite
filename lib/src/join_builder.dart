import 'package:meta/meta.dart';

/// Types of SQL joins supported by the query builder
enum JoinType {
  /// INNER JOIN
  inner('INNER JOIN'),

  /// LEFT JOIN (LEFT OUTER JOIN)
  left('LEFT JOIN'),

  /// RIGHT JOIN (RIGHT OUTER JOIN)  
  right('RIGHT JOIN'),

  /// FULL OUTER JOIN
  fullOuter('FULL OUTER JOIN'),

  /// CROSS JOIN
  cross('CROSS JOIN');

  const JoinType(this.sqlKeyword);

  /// The SQL keyword for this join type
  final String sqlKeyword;

  @override
  String toString() => sqlKeyword;
}

/// Builder for SQL JOIN clauses in SELECT statements.
/// 
/// Supports different join types with ON conditions using fluent syntax.
@immutable
class JoinBuilder {
  const JoinBuilder._({
    required this.joinType,
    required this.tableName,
    this.tableAlias,
    this.onCondition,
  });

  /// Creates a new JOIN clause
  JoinBuilder(this.joinType, this.tableName)
      : tableAlias = null,
        onCondition = null;

  /// The type of join to perform
  final JoinType joinType;

  /// The table to join with
  final String tableName;

  /// Optional alias for the joined table
  final String? tableAlias;

  /// The ON condition for the join
  final String? onCondition;

  /// Adds an alias to the joined table
  JoinBuilder as(String alias) {
    return JoinBuilder._(
      joinType: joinType,
      tableName: tableName,
      tableAlias: alias,
      onCondition: onCondition,
    );
  }

  /// Adds an ON condition to the join
  JoinBuilder on(String condition) {
    return JoinBuilder._(
      joinType: joinType,
      tableName: tableName,
      tableAlias: tableAlias,
      onCondition: condition,
    );
  }

  /// Convenience method for equi-join condition
  JoinBuilder onEquals(String leftColumn, String rightColumn) {
    return on('$leftColumn = $rightColumn');
  }

  /// Generates the SQL representation of this join
  String toSql() {
    final buffer = StringBuffer();
    
    buffer.write(joinType.sqlKeyword);
    buffer.write(' $tableName');
    
    if (tableAlias != null) {
      buffer.write(' AS $tableAlias');
    }
    
    if (onCondition != null) {
      buffer.write(' ON $onCondition');
    }
    
    return buffer.toString();
  }

  @override
  String toString() => toSql();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoinBuilder &&
          runtimeType == other.runtimeType &&
          joinType == other.joinType &&
          tableName == other.tableName &&
          tableAlias == other.tableAlias &&
          onCondition == other.onCondition;

  @override
  int get hashCode =>
      joinType.hashCode ^
      tableName.hashCode ^
      tableAlias.hashCode ^
      onCondition.hashCode;
}

/// Helper class for creating common join patterns
class Joins {
  /// Creates an INNER JOIN
  static JoinBuilder inner(String tableName) => JoinBuilder(JoinType.inner, tableName);

  /// Creates a LEFT JOIN
  static JoinBuilder left(String tableName) => JoinBuilder(JoinType.left, tableName);

  /// Creates a RIGHT JOIN
  static JoinBuilder right(String tableName) => JoinBuilder(JoinType.right, tableName);

  /// Creates a FULL OUTER JOIN
  static JoinBuilder fullOuter(String tableName) => JoinBuilder(JoinType.fullOuter, tableName);

  /// Creates a CROSS JOIN
  static JoinBuilder cross(String tableName) => JoinBuilder(JoinType.cross, tableName);
}