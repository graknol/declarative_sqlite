import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:equatable/equatable.dart';

class DirtyRow extends Equatable {
  final String tableName;
  final String rowId;
  final Hlc hlc;
  final bool isFullRow; // true if full row should be sent, false if only LWW columns
  final Map<String, Object?>? data; // The changed values (optional for backward compatibility)

  @override
  List<Object?> get props => [tableName, rowId, hlc, isFullRow, data];

  const DirtyRow({
    required this.tableName,
    required this.rowId,
    required this.hlc,
    required this.isFullRow,
    this.data,
  });
}
