import 'package:declarative_sqlite/src/sync/operation.dart';
import 'package:declarative_sqlite/src/sync/operation_store.dart';
import 'package:sqflite_common/sqlite_api.dart';

class MockOperationStore implements OperationStore {
  @override
  Future<void> add(Operation operation) async {}

  @override
  Future<List<Operation>> getAll() async => [];

  @override
  Future<void> init(DatabaseExecutor db) async {}

  @override
  Future<void> remove(List<Operation> operations) async {}
}
