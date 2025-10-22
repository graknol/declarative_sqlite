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

  /// A stream that emits dirty rows as they are added to the store.
  /// 
  /// This stream allows consumers to reactively respond to database changes
  /// instead of polling for dirty rows. Each emission contains the DirtyRow
  /// that was just added to the store.
  /// 
  /// Example usage:
  /// ```dart
  /// database.dirtyRowStore?.onRowAdded.listen((dirtyRow) {
  ///   print('New dirty row: ${dirtyRow.tableName} ${dirtyRow.rowId}');
  ///   // Trigger sync logic here
  ///   syncService.sync();
  /// });
  /// ```
  Stream<DirtyRow> get onRowAdded;

  /// Disposes of any resources used by the store.
  /// 
  /// This should be called when the store is no longer needed to clean up
  /// stream controllers and other resources.
  Future<void> dispose();
}
