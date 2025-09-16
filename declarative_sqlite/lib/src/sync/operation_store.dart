import 'package:declarative_sqlite/src/sync/operation.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Abstract base class for a data store that holds pending operations.
abstract class OperationStore {
  /// Initializes the store with a database executor.
  Future<void> init(DatabaseExecutor db);

  /// Adds an operation to the store.
  Future<void> add(Operation operation);

  /// Retrieves all pending operations from the store.
  Future<List<Operation>> getAll();

  /// Removes a list of operations from the store, usually after they have been
  /// successfully synchronized.
  Future<void> remove(List<Operation> operations);
}
