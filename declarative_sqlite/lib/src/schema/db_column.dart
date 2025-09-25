import 'package:declarative_sqlite/src/utils/sql_escaping_utils.dart';

/// Callback function type for generating default values dynamically
typedef DefaultValueCallback = Object? Function();

class DbColumn {
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
  final DefaultValueCallback? defaultValueCallback;

  const DbColumn({
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
    this.defaultValueCallback,
  });

  String toSql() {
    assert(
      !isNotNull || defaultValue != null || defaultValueCallback != null,
      'defaultValue or defaultValueCallback is required when column is marked as "NOT NULL".',
    );

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

  Object? getDefaultValue() {
    return defaultValueCallback != null
        ? defaultValueCallback!()
        : defaultValue;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'logicalType': logicalType,
        'type': type,
        'isNotNull': isNotNull,
        'defaultValue': defaultValue.toString(), // Store as string
        'isParent': isParent,
        'isLww': isLww,
        'minValue': minValue,
        'maxValue': maxValue,
      };

  factory DbColumn.fromJson(Map<String, dynamic> json) => DbColumn(
        name: json['name'],
        logicalType: json['logicalType'],
        type: json['type'],
        isNotNull: json['isNotNull'],
        defaultValue: json['defaultValue'],
        isParent: json['isParent'],
        isLww: json['isLww'],
        minValue: json['minValue'],
        maxValue: json['maxValue'],
      );
}
