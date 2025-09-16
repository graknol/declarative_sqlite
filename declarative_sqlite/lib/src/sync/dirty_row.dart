import 'package:declarative_sqlite/src/sync/hlc.dart';

class DirtyRow {
  final String tableName;
  final String rowId;
  final Hlc hlc;

  DirtyRow({
    required this.tableName,
    required this.rowId,
    required this.hlc,
  });
}
