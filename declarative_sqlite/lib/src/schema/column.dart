class Column {
  final String name;
  final String type;
  final bool isNotNull;
  final num? minValue;
  final num? maxValue;
  final int? maxLength;
  final bool isParent;
  final bool isSequence;
  final bool sequencePerParent;
  final bool isLww;
  final int? maxFileSizeMb;
  final int? maxCount;
  final Object? defaultValue;

  const Column({
    required this.name,
    required this.type,
    this.isNotNull = false,
    this.minValue,
    this.maxValue,
    this.maxLength,
    this.isParent = false,
    this.isSequence = false,
    this.sequencePerParent = false,
    this.isLww = false,
    this.maxFileSizeMb,
    this.maxCount,
    this.defaultValue,
  });
}
