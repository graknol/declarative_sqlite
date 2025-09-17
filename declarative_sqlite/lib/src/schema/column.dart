import 'package:declarative_sqlite/src/utils/sql_escaping_utils.dart';

class Column {
  final String name;
  final String logicalType;
  final String type; // The actual DB type (e.g., TEXT, INTEGER)
  final bool isNotNull;
  final num? minValue;
  final num? maxValue;
  final int? maxLength;
  final bool isParent;
  final bool isSequence;
  final bool sequencePerParent;
  final bool isLww;
  final Object? defaultValue;

  const Column({
    required this.name,
    required this.logicalType,
    required this.type,
    this.isNotNull = false,
    this.minValue,
    this.maxValue,
    this.maxLength,
    this.isParent = false,
    this.isSequence = false,
    this.sequencePerParent = false,
    this.isLww = false,
    this.defaultValue,
  });

  String toSql() {
    final parts = [name, type];
    if (isNotNull) {
      parts.add('NOT NULL');
    }
    if (defaultValue != null) {
      if (defaultValue is String) {
        parts.add("DEFAULT '${escapeSingleQuotes(defaultValue as String)}'");
      } else {
        parts.add('DEFAULT $defaultValue');
      }
    }
  if (minValue != null) {
    parts.add('CHECK($name >= $minValue)');
  }
  if (maxLength != null) {
    parts.add('CHECK(length($name) <= $maxLength)');
  }

    return parts.join(' ');
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'logicalType': logicalType,
      'type': type,
      'isNotNull': isNotNull,
      'minValue': minValue,
      'maxValue': maxValue,
      'maxLength': maxLength,
      'isParent': isParent,
      'isSequence': isSequence,
      'sequencePerParent': sequencePerParent,
      'isLww': isLww,
      'defaultValue': defaultValue,
    };
  }
}
