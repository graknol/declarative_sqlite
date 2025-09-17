import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:equatable/equatable.dart';

class DirtyRow extends Equatable {
  final String tableName;
  final String rowId;
  final Hlc hlc;

  @override
  List<Object?> get props => [tableName, rowId, hlc];

  const DirtyRow({
    required this.tableName,
    required this.rowId,
    required this.hlc,
  });
}
