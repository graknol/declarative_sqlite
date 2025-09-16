import 'package:declarative_sqlite/src/sync/dirty_row.dart';
import 'package:declarative_sqlite/src/database.dart';

typedef OnFetch = Future<void> Function(
    DeclarativeDatabase database, String table, DateTime? lastSynced);

typedef OnSend = Future<bool> Function(List<DirtyRow> operations);
