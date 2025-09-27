import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:equatable/equatable.dart';

class DirtyRow extends Equatable {
  final String tableName;
  final String rowId;
  final Hlc hlc;
  final bool isFullRow; // true if full row should be sent, false if only LWW columns

  @override
  List<Object?> get props => [tableName, rowId, hlc, isFullRow];

  const DirtyRow({
    required this.tableName,
    required this.rowId,
    required this.hlc,
    required this.isFullRow,
  });
}
