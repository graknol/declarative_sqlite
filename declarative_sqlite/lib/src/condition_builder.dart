import 'package:meta/meta.dart';
import 'package:equatable/equatable.dart';

/// A composable condition builder for creating complex WHERE clauses with proper grouping.
/// 
/// Supports functional programming principles with composable and(), or(), not() operations
/// and comparison operators like eq(), lt(), gt(), between(), in(), etc.
@immutable
class ConditionBuilder extends Equatable {
  /// The SQL condition expression
  final String expression;
  
  /// The arguments for parameterized queries
  final List<dynamic> arguments;

  ConditionBuilder._({
    required this.expression,
    required this.arguments,
  });

  /// Creates a simple condition
  ConditionBuilder(String expression, [List<dynamic>? arguments])
      : expression = expression,
        arguments = arguments ?? const [];

  /// Creates an equality condition
  factory ConditionBuilder.eq(String column, dynamic value) {
    return ConditionBuilder('$column = ?', [value]);
  }

  /// Creates a not equal condition
  factory ConditionBuilder.ne(String column, dynamic value) {
    return ConditionBuilder('$column != ?', [value]);
  }

  /// Creates a less than condition
  factory ConditionBuilder.lt(String column, dynamic value) {
    return ConditionBuilder('$column < ?', [value]);
  }

  /// Creates a less than or equal condition
  factory ConditionBuilder.le(String column, dynamic value) {
    return ConditionBuilder('$column <= ?', [value]);
  }

  /// Creates a greater than condition
  factory ConditionBuilder.gt(String column, dynamic value) {
    return ConditionBuilder('$column > ?', [value]);
  }

  /// Creates a greater than or equal condition
  factory ConditionBuilder.ge(String column, dynamic value) {
    return ConditionBuilder('$column >= ?', [value]);
  }

  /// Creates a LIKE condition
  factory ConditionBuilder.like(String column, String pattern) {
    return ConditionBuilder('$column LIKE ?', [pattern]);
  }

  /// Creates a NOT LIKE condition
  factory ConditionBuilder.notLike(String column, String pattern) {
    return ConditionBuilder('$column NOT LIKE ?', [pattern]);
  }

  /// Creates an IN condition
  factory ConditionBuilder.inList(String column, List<dynamic> values) {
    if (values.isEmpty) {
      return ConditionBuilder('1 = 0'); // Always false for empty list
    }
    final placeholders = List.filled(values.length, '?').join(', ');
    return ConditionBuilder('$column IN ($placeholders)', values);
  }

  /// Creates a NOT IN condition
  factory ConditionBuilder.notInList(String column, List<dynamic> values) {
    if (values.isEmpty) {
      return ConditionBuilder('1 = 1'); // Always true for empty list
    }
    final placeholders = List.filled(values.length, '?').join(', ');
    return ConditionBuilder('$column NOT IN ($placeholders)', values);
  }

  /// Creates a BETWEEN condition
  factory ConditionBuilder.between(String column, dynamic from, dynamic to) {
    return ConditionBuilder('$column BETWEEN ? AND ?', [from, to]);
  }

  /// Creates a NOT BETWEEN condition
  factory ConditionBuilder.notBetween(String column, dynamic from, dynamic to) {
    return ConditionBuilder('$column NOT BETWEEN ? AND ?', [from, to]);
  }

  /// Creates an IS NULL condition
  factory ConditionBuilder.isNull(String column) {
    return ConditionBuilder('$column IS NULL');
  }

  /// Creates an IS NOT NULL condition
  factory ConditionBuilder.isNotNull(String column) {
    return ConditionBuilder('$column IS NOT NULL');
  }

  /// Creates a raw condition (use with caution)
  factory ConditionBuilder.raw(String expression, [List<dynamic>? arguments]) {
    return ConditionBuilder(expression, arguments);
  }

  /// Combines this condition with another using AND
  ConditionBuilder and(ConditionBuilder other) {
    return ConditionBuilder._(
      expression: '($expression) AND (${other.expression})',
      arguments: [...arguments, ...other.arguments],
    );
  }

  /// Combines this condition with another using OR
  ConditionBuilder or(ConditionBuilder other) {
    return ConditionBuilder._(
      expression: '($expression) OR (${other.expression})',
      arguments: [...arguments, ...other.arguments],
    );
  }

  /// Negates this condition using NOT
  ConditionBuilder not() {
    return ConditionBuilder._(
      expression: 'NOT ($expression)',
      arguments: arguments,
    );
  }

  /// Groups this condition in parentheses (for explicit grouping)
  ConditionBuilder group() {
    return ConditionBuilder._(
      expression: '($expression)',
      arguments: arguments,
    );
  }

  /// Combines multiple conditions with AND
  static ConditionBuilder andAll(List<ConditionBuilder> conditions) {
    if (conditions.isEmpty) {
      throw ArgumentError('At least one condition is required');
    }
    if (conditions.length == 1) {
      return conditions.first;
    }

    return conditions.skip(1).fold(
      conditions.first,
      (result, condition) => result.and(condition),
    );
  }

  /// Combines multiple conditions with OR
  static ConditionBuilder orAll(List<ConditionBuilder> conditions) {
    if (conditions.isEmpty) {
      throw ArgumentError('At least one condition is required');
    }
    if (conditions.length == 1) {
      return conditions.first;
    }

    return conditions.skip(1).fold(
      conditions.first,
      (result, condition) => result.or(condition),
    );
  }

  /// Generates the SQL representation of this condition
  String toSql() {
    return expression;
  }

  /// Gets all arguments in the correct order
  List<dynamic> getArguments() {
    return List.unmodifiable(arguments);
  }

  @override
  List<Object?> get props => [expression, arguments];

  @override
  String toString() => 'ConditionBuilder(${toSql()}, args: $arguments)';
}

/// Commonly used condition patterns
class Conditions {
  Conditions._();

  /// Creates an equality condition
  static ConditionBuilder eq(String column, dynamic value) =>
      ConditionBuilder.eq(column, value);

  /// Creates a not equal condition  
  static ConditionBuilder ne(String column, dynamic value) =>
      ConditionBuilder.ne(column, value);

  /// Creates a less than condition
  static ConditionBuilder lt(String column, dynamic value) =>
      ConditionBuilder.lt(column, value);

  /// Creates a less than or equal condition
  static ConditionBuilder le(String column, dynamic value) =>
      ConditionBuilder.le(column, value);

  /// Creates a greater than condition
  static ConditionBuilder gt(String column, dynamic value) =>
      ConditionBuilder.gt(column, value);

  /// Creates a greater than or equal condition
  static ConditionBuilder ge(String column, dynamic value) =>
      ConditionBuilder.ge(column, value);

  /// Creates a LIKE condition
  static ConditionBuilder like(String column, String pattern) =>
      ConditionBuilder.like(column, pattern);

  /// Creates a NOT LIKE condition
  static ConditionBuilder notLike(String column, String pattern) =>
      ConditionBuilder.notLike(column, pattern);

  /// Creates an IN condition
  static ConditionBuilder inList(String column, List<dynamic> values) =>
      ConditionBuilder.inList(column, values);

  /// Creates a NOT IN condition
  static ConditionBuilder notInList(String column, List<dynamic> values) =>
      ConditionBuilder.notInList(column, values);

  /// Creates a BETWEEN condition
  static ConditionBuilder between(String column, dynamic from, dynamic to) =>
      ConditionBuilder.between(column, from, to);

  /// Creates a NOT BETWEEN condition
  static ConditionBuilder notBetween(String column, dynamic from, dynamic to) =>
      ConditionBuilder.notBetween(column, from, to);

  /// Creates an IS NULL condition
  static ConditionBuilder isNull(String column) =>
      ConditionBuilder.isNull(column);

  /// Creates an IS NOT NULL condition
  static ConditionBuilder isNotNull(String column) =>
      ConditionBuilder.isNotNull(column);

  /// Creates a raw condition
  static ConditionBuilder raw(String expression, [List<dynamic>? arguments]) =>
      ConditionBuilder.raw(expression, arguments);

  /// Combines multiple conditions with AND
  static ConditionBuilder andAll(List<ConditionBuilder> conditions) =>
      ConditionBuilder.andAll(conditions);

  /// Combines multiple conditions with OR
  static ConditionBuilder orAll(List<ConditionBuilder> conditions) =>
      ConditionBuilder.orAll(conditions);
}