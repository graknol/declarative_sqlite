import 'package:declarative_sqlite/src/sync/dirty_row.dart';
import 'package:declarative_sqlite/src/sync/dirty_row_store.dart';
import 'package:sqflite_common/sqlite_api.dart';

class MockOperationStore implements DirtyRowStore {
  @override
  Future<void> add(DirtyRow operation) async {}

  @override
  Future<List<DirtyRow>> getAll() async => [];

  @override
  Future<void> init(DatabaseExecutor db) async {}

  @override
  Future<void> remove(List<DirtyRow> operations) async {}
}
