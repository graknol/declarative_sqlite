import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:declarative_sqlite/src/sync/dirty_row.dart';
import 'package:sqflite_common/sqflite.dart';

/// Abstract base class for a data store that holds pending operations.
abstract class DirtyRowStore {
  /// Initializes the store with the [DatabaseExecutor].
  Future<void> init(DatabaseExecutor db);

  /// Adds an operation to the store.
  Future<void> add(String tableName, String rowId, Hlc hlc, bool isFullRow);

  /// Retrieves all pending operations from the store.
  Future<List<DirtyRow>> getAll();

  /// Removes a list of operations from the store, usually after they have been
  /// successfully synchronized.
  Future<void> remove(List<DirtyRow> operations);

  /// Clears all pending operations from the store.
  Future<void> clear();
}
