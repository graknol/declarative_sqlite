import 'package:declarative_sqlite/src/sync/operation.dart';
import 'package:declarative_sqlite/src/database.dart';

typedef OnFetch = Future<void> Function(
    DataAccess dataAccess, String table, DateTime? lastSynced);

typedef OnSend = Future<bool> Function(List<Operation> operations);
