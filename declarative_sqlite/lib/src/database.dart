import 'dart:async';

import 'package:declarative_sqlite/src/builders/query_builder.dart';
import 'package:declarative_sqlite/src/schema/schema.dart';
import 'package:declarative_sqlite/src/sync/operation.dart';
import 'package:declarative_sqlite/src/sync/operation_store.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;

import 'data_mapping.dart';
import 'migration/generate_migration_scripts.dart';
import 'migration/introspect_schema.dart';
import 'migration/schema_diff.dart';

/// A declarative wrapper around a sqflite database.
class DeclarativeDatabase {
  /// The underlying sqflite database.
  ///
  /// This is exposed for advanced use cases, but it's recommended to use the
  /// declarative API as much as possible.
  sqflite.Database get db => _db;
  final sqflite.Database _db;

  /// The schema for the database.
  final Schema _schema;
  Schema get schema => _schema;

  final OperationStore _operationStore;

  /// Returns an object that can be used to perform database operations
  /// that are not logged for synchronization purposes.
  late final DataAccess dataAccess;

  sqflite.DatabaseExecutor get _executor => _txn ?? _db;
  final sqflite.Transaction? _txn;

  DeclarativeDatabase._internal(this._db, this._schema, this._operationStore)
      : _txn = null {
    dataAccess = DataAccess(this);
  }

  /// Private constructor for use within transactions.
  DeclarativeDatabase._inTransaction(
    this._db,
    this._schema,
    this._operationStore,
    this._txn,
  ) {
    dataAccess = DataAccess(this);
  }

  /// Opens the database and performs any necessary migrations.
  static Future<DeclarativeDatabase> open(
    String path, {
    required sqflite.DatabaseFactory databaseFactory,
    required Schema schema,
    required OperationStore operationStore,
  }) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: schema.version,
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final table in schema.tables) {
            final columns = table.columns.map((c) => c.toSql()).join(',\n  ');
            batch.execute('CREATE TABLE ${table.name} (\n  $columns\n)');
          }
          for (final view in schema.views) {
            batch.execute(view.toSql());
          }
          await batch.commit();
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          final liveSchema = await introspectSchema(db);
          final diff = diffSchemas(schema, liveSchema);
          final migrationScripts = generateMigrationScripts(diff.changes);

          await db.transaction((txn) async {
            for (final script in migrationScripts) {
              await txn.execute(script);
            }
          });
        },
      ),
    );

    await operationStore.init(db);

    return DeclarativeDatabase._internal(db, schema, operationStore);
  }

  /// Closes the database.
  Future<void> close() => _db.close();

  Future<List<Operation>> getPendingOperations() => _operationStore.getAll();

  Future<void> clearPendingOperations(List<Operation> operations) =>
      _operationStore.remove(operations);

  /// Executes a transaction.
  ///
  /// The [action] callback will be called with a new [DeclarativeDatabase]
  /// instance that is bound to the transaction. All operations performed on
  /// this instance will be executed within the transaction.
  Future<T> transaction<T>(
    Future<T> Function(DeclarativeDatabase txnDb) action, {
    bool? exclusive,
  }) async {
    // If we are already in a transaction, just execute the action with the
    // current transaction-aware database instance.
    if (_txn != null) {
      return await action(this);
    }

    return await _db.transaction((txn) async {
      final txnDb = DeclarativeDatabase._inTransaction(
        _db,
        _schema,
        _operationStore,
        txn,
      );
      return await action(txnDb);
    }, exclusive: exclusive);
  }

  /// Executes a raw SQL query on the database and returns the results.
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? whereArgs,
  ]) async {
    return _executor.rawQuery(sql, whereArgs);
  }

  /// A convenience method for executing a query using a [QueryBuilder].
  Future<List<Map<String, Object?>>> query(
    QueryBuilder builder,
  ) async {
    final (sql, params) = builder.build();
    return rawQuery(sql, params);
  }

  /// Queries a table and returns the results.
  Future<List<Map<String, Object?>>> queryTable(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return _executor.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Inserts a row into a table.
  ///
  /// If [logOperation] is true, the operation will be logged for
  /// synchronization.
  Future<int> insert(
    String table,
    Map<String, dynamic> values, {
    bool logOperation = true,
  }) async {
    final id = await _executor.insert(table, values);
    if (logOperation) {
      final pk = _schema.tables
          .firstWhere((t) => t.name == table)
          .keys
          .firstWhere((k) => k.isPrimary)
          .columns
          .first;
      await _operationStore.add(Operation(
        tableName: table,
        rowId: values[pk].toString(),
        type: OperationType.insert,
        data: values,
        timestamp: DateTime.now(),
      ));
    }
    return id;
  }

  /// Updates a row in a table.
  ///
  /// If [logOperation] is true, the operation will be logged for
  /// synchronization.
  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    required String where,
    required List<Object?> whereArgs,
    bool logOperation = true,
  }) async {
    final count = await _executor.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
    if (logOperation) {
      // This is a simplification. In a real app, you'd need a more robust
      // way to identify the updated rows and log them.
      final pk = _schema.tables
          .firstWhere((t) => t.name == table)
          .keys
          .firstWhere((k) => k.isPrimary)
          .columns
          .first;
      final updatedRows =
          await queryTable(table, where: where, whereArgs: whereArgs);
      for (final row in updatedRows) {
        await _operationStore.add(Operation(
          tableName: table,
          rowId: row[pk] as String,
          type: OperationType.update,
          data: values,
          timestamp: DateTime.now(),
        ));
      }
    }
    return count;
  }

  /// Deletes a row from a table.
  ///
  /// If [logOperation] is true, the operation will be logged for
  /// synchronization.
  Future<int> delete(
    String table, {
    required String where,
    required List<Object?> whereArgs,
    bool logOperation = true,
  }) async {
    if (logOperation) {
      final pk = _schema.tables
          .firstWhere((t) => t.name == table)
          .keys
          .firstWhere((k) => k.isPrimary)
          .columns
          .first;
      final rowsToDelete =
          await queryTable(table, where: where, whereArgs: whereArgs);
      for (final row in rowsToDelete) {
        await _operationStore.add(Operation(
          tableName: table,
          rowId: row[pk] as String,
          type: OperationType.delete,
          timestamp: DateTime.now(),
        ));
      }
    }
    return await _executor.delete(table, where: where, whereArgs: whereArgs);
  }

  /// Executes a query and maps the results to a list of objects.
  /// Queries the database and maps the results to a list of objects.
  Future<List<T>> queryMapped<T>(DataMapper<T> mapper,
      {String? where, List<Object?>? whereArgs}) async {
    final results = await queryTable(
      mapper.tableName,
      where: where,
      whereArgs: whereArgs,
    );
    return results.map((row) => mapper.fromMap(row)).toList();
  }
}

/// Provides access to database operations that are not logged for
/// synchronization.
class DataAccess {
  final DeclarativeDatabase _db;

  DataAccess(this._db);

  /// Loads a list of data into a table.
  ///
  /// This is useful for loading data from a server without triggering
  /// synchronization operations.
  Future<void> bulkLoad(
      String tableName, List<Map<String, dynamic>> data) async {
    if (data.isEmpty) {
      return;
    }
    await _db.transaction((txn) async {
      for (final row in data) {
        await txn.insert(
          tableName,
          row,
          logOperation: false, // Don't log these operations
        );
      }
    });
  }
}
