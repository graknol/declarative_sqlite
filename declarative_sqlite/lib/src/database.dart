import 'dart:async';
import 'dart:convert';

import 'package:declarative_sqlite/src/builders/query_builder.dart';
import 'package:declarative_sqlite/src/schema/schema.dart';
import 'package:declarative_sqlite/src/sync/operation.dart';
import 'package:declarative_sqlite/src/sync/operation_store.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;

import 'data_mapping.dart';
import 'migration/generate_migration_scripts.dart';
import 'migration/introspect_schema.dart';
import 'migration/schema_diff.dart';

/// A declarative wrapper around a sqflite database, providing a fluent API
/// for database operations, automatic schema migrations, and operation logging
/// for synchronization.
///
/// The main purpose of this class is to abstract away the complexities of
/// managing a SQLite database, allowing you to define your schema declaratively
/// and interact with the database in a type-safe manner.
///
/// Example:
/// ```dart
/// // 1. Define a schema
/// final schemaBuilder = SchemaBuilder();
/// schemaBuilder.table('users', (table) {
///   table.guid('id').notNull(Uuid().v4());
///   table.text('name').notNull('Default Name');
/// });
/// final schema = schemaBuilder.build();
///
/// // 2. Open the database
/// final db = await DeclarativeDatabase.open(
///   'my_database.db',
///   databaseFactory: databaseFactory, // from sqflite_common_ffi on desktop
///   schema: schema,
///   operationStore: SqliteOperationStore(),
/// );
///
/// // 3. Insert data
/// await db.insert('users', {'id': '1', 'name': 'Alice'});
///
/// // 4. Query data
/// final users = await db.query(QueryBuilder().from('users'));
/// print(users);
///
/// // 5. Close the database
/// await db.close();
/// ```
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

  /// Opens the database, creates the schema if it doesn't exist, and runs
  /// any necessary migrations.
  ///
  /// The [path] is the path to the database file, or `:memory:` for an
  /// in-memory database.
  /// The [databaseFactory] is the sqflite database factory to use. This allows
  /// the library to be platform-agnostic.
  /// The [schema] is the declarative schema for the database.
  /// The [operationStore] is the store for pending synchronization operations.
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
  ///
  /// It's important to close the database when it's no longer needed to free
  /// up resources.
  Future<void> close() => _db.close();

  /// Retrieves all pending synchronization operations from the operation store.
  Future<List<Operation>> getPendingOperations() => _operationStore.getAll();

  /// Removes a list of successfully synchronized operations from the store.
  Future<void> clearPendingOperations(List<Operation> operations) =>
      _operationStore.remove(operations);

  /// Executes a transaction.
  ///
  /// The [action] callback will be called with a new [DeclarativeDatabase]
  /// instance that is bound to the transaction. All operations performed on
  /// this instance will be executed within the transaction.
  ///
  /// Example:
  /// ```dart
  /// await db.transaction((txnDb) async {
  ///   await txnDb.insert('users', {'id': '1', 'name': 'Alice'});
  ///   await txnDb.insert('users', {'id': '2', 'name': 'Bob'});
  /// });
  /// ```
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
  ///
  /// This is useful for executing complex queries that are not easily
  /// expressible with the [QueryBuilder].
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? whereArgs,
  ]) async {
    return _executor.rawQuery(sql, whereArgs);
  }

  /// A convenience method for executing a query using a [QueryBuilder].
  ///
  /// Example:
  /// ```dart
  /// final builder = QueryBuilder().from('users').where(col('age').gt(18));
  /// final results = await db.query(builder);
  /// ```
  Future<List<Map<String, Object?>>> query(
    QueryBuilder builder,
  ) async {
    final (sql, params) = builder.build();
    return rawQuery(sql, params);
  }

  /// Queries a table and returns the results.
  ///
  /// This is a convenience method for simple queries. For more complex
  /// queries, use the [QueryBuilder] and the [query] method.
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
  /// If [logOperation] is true (the default), the operation will be logged
  /// for synchronization.
  /// The [conflictAlgorithm] specifies how to handle conflicts if a row with
  /// the same primary key already exists.
  ///
  /// Example:
  /// ```dart
  /// await db.insert('users', {'id': '1', 'name': 'Alice'});
  /// ```
  Future<int> insert(
    String table,
    Map<String, dynamic> values, {
    bool logOperation = true,
    sqflite.ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final id = await _executor.insert(
      table,
      values,
      conflictAlgorithm: conflictAlgorithm,
    );
    if (logOperation) {
      final pk = _schema.tables
          .firstWhere((t) => t.name == table)
          .keys
          .firstWhere((k) => k.isPrimary);

      final rowId = _getRowId(pk.columns, values);

      await _operationStore.add(Operation(
        tableName: table,
        rowId: rowId,
        type: OperationType.insert,
        data: values,
        timestamp: DateTime.now(),
      ));
    }
    return id;
  }

  /// Updates a row in a table.
  ///
  /// If [logOperation] is true (the default), the operation will be logged
  /// for synchronization.
  ///
  /// Example:
  /// ```dart
  /// await db.update(
  ///   'users',
  ///   {'name': 'Alicia'},
  ///   where: 'id = ?',
  ///   whereArgs: ['1'],
  /// );
  /// ```
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
      // way to identify the updated rows and log them.
      final pk = _schema.tables
          .firstWhere((t) => t.name == table)
          .keys
          .firstWhere((k) => k.isPrimary);
      final updatedRows =
          await queryTable(table, where: where, whereArgs: whereArgs);
      for (final row in updatedRows) {
        final rowId = _getRowId(pk.columns, row);
        await _operationStore.add(Operation(
          tableName: table,
          rowId: rowId,
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
  /// If [logOperation] is true (the default), the operation will be logged
  /// for synchronization.
  ///
  /// Example:
  /// ```dart
  /// await db.delete('users', where: 'id = ?', whereArgs: ['1']);
  /// ```
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
          .firstWhere((k) => k.isPrimary);
      final rowsToDelete =
          await queryTable(table, where: where, whereArgs: whereArgs);
      for (final row in rowsToDelete) {
        final rowId = _getRowId(pk.columns, row);
        await _operationStore.add(Operation(
          tableName: table,
          rowId: rowId,
          type: OperationType.delete,
          timestamp: DateTime.now(),
        ));
      }
    }
    return await _executor.delete(table, where: where, whereArgs: whereArgs);
  }

  String _getRowId(List<String> pkColumnNames, Map<String, dynamic> row) {
    if (pkColumnNames.length == 1) {
      return row[pkColumnNames.first].toString();
    } else {
      final pkValues = <String, dynamic>{};
      for (final colName in pkColumnNames) {
        pkValues[colName] = row[colName];
      }
      return jsonEncode(pkValues);
    }
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

  /// Loads a list of data into a table, replacing any existing rows with the
  /// same primary key.
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
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
    });
  }
}
