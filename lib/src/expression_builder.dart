import 'package:meta/meta.dart';

/// Builder for SQL expressions used in SELECT statements.
/// 
/// Supports column references, literals, functions, and aliases with fluent syntax.
@immutable
class ExpressionBuilder {
  const ExpressionBuilder._({
    required this.expression,
    this.alias,
  });

  /// Creates a column reference expression
  ExpressionBuilder.column(String columnName) 
      : expression = columnName,
        alias = null;

  /// Creates a qualified column reference (table.column)
  ExpressionBuilder.qualifiedColumn(String tableName, String columnName)
      : expression = '$tableName.$columnName',
        alias = null;

  /// Creates a literal value expression
  ExpressionBuilder.literal(dynamic value)
      : expression = _formatLiteral(value),
        alias = null;

  /// Creates a function call expression
  ExpressionBuilder.function(String functionName, [List<String> arguments = const []])
      : expression = '$functionName(${arguments.join(', ')})',
        alias = null;

  /// Creates a raw SQL expression
  ExpressionBuilder.raw(String sql)
      : expression = sql,
        alias = null;

  /// The SQL expression
  final String expression;

  /// Optional alias for the expression
  final String? alias;

  /// Adds an alias to this expression
  ExpressionBuilder as(String aliasName) {
    return ExpressionBuilder._(
      expression: expression,
      alias: aliasName,
    );
  }

  /// Generates the SQL representation of this expression
  String toSql() {
    if (alias != null) {
      return '$expression $alias';
    }
    return expression;
  }

  /// Formats a literal value for SQL
  static String _formatLiteral(dynamic value) {
    if (value == null) {
      return 'NULL';
    } else if (value is String) {
      return "'${value.replaceAll("'", "''")}'";
    } else if (value is num) {
      return value.toString();
    } else if (value is bool) {
      return value ? '1' : '0';
    } else {
      return "'${value.toString().replaceAll("'", "''")}'";
    }
  }

  @override
  String toString() => toSql();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpressionBuilder &&
          runtimeType == other.runtimeType &&
          expression == other.expression &&
          alias == other.alias;

  @override
  int get hashCode => expression.hashCode ^ alias.hashCode;
}

/// Commonly used SQL expressions
class Expressions {
  /// COUNT(*) expression
  static ExpressionBuilder get count => ExpressionBuilder.function('COUNT', ['*']);

  /// COUNT(column) expression
  static ExpressionBuilder countColumn(String column) => 
      ExpressionBuilder.function('COUNT', [column]);

  /// SUM(column) expression
  static ExpressionBuilder sum(String column) =>
      ExpressionBuilder.function('SUM', [column]);

  /// AVG(column) expression
  static ExpressionBuilder avg(String column) =>
      ExpressionBuilder.function('AVG', [column]);

  /// MAX(column) expression
  static ExpressionBuilder max(String column) =>
      ExpressionBuilder.function('MAX', [column]);

  /// MIN(column) expression
  static ExpressionBuilder min(String column) =>
      ExpressionBuilder.function('MIN', [column]);

  /// DISTINCT column expression
  static ExpressionBuilder distinct(String column) =>
      ExpressionBuilder.raw('DISTINCT $column');

  /// ALL columns (*)
  static ExpressionBuilder get all => ExpressionBuilder.raw('*');
}