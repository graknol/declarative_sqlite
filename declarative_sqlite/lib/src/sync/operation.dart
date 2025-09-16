enum OperationType { insert, update, delete }

class Operation {
  final int? id;
  final OperationType type;
  final String tableName;
  final String rowId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  Operation({
    this.id,
    required this.type,
    required this.tableName,
    required this.rowId,
    this.data,
    required this.timestamp,
  });
}
