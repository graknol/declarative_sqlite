import 'dart:async';
import 'dart:convert';

import 'package:declarative_sqlite/src/builders/query_builder.dart';
import 'package:declarative_sqlite/src/schema/schema.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';
import 'package:declarative_sqlite/src/sync/operation.dart';
import 'package:declarative_sqlite/src/sync/operation_store.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;
import 'package:uuid/uuid.dart';

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

  /// The Hybrid Logical Clock for generating timestamps.
  final HlcClock _hlcClock;

  /// Returns an object that can be used to perform database operations
  /// that are not logged for synchronization purposes.
  late final DataAccess dataAccess;

  sqflite.DatabaseExecutor get _executor => _txn ?? _db;
  final sqflite.Transaction? _txn;

  DeclarativeDatabase._internal(
    this._db,
    this._schema,
    this._operationStore,
    this._hlcClock,
  ) : _txn = null {
    dataAccess = DataAccess(this);
  }

  /// Private constructor for use within transactions.
  DeclarativeDatabase._inTransaction(
    this._db,
    this._schema,
    this._operationStore,
    this._hlcClock,
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
    // Ensure settings table exists before anything else
    final db = await databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(),
    );

    await _createSystemTables(db);

    final currentSchemaHash = schema.toHash();
    String? storedSchemaHash;
    final resultSchemaHash = await db.query(
      '__settings',
      where: 'key = ?',
      whereArgs: ['schema_hash'],
    );
    if (resultSchemaHash.isNotEmpty) {
      storedSchemaHash = resultSchemaHash.first['value'] as String?;
    }

    if (currentSchemaHash != storedSchemaHash) {
      final liveSchema = await introspectSchema(db);
      final diff = diffSchemas(schema, liveSchema);
      final migrationScripts = generateMigrationScripts(diff.changes);

      await db.transaction((txn) async {
        for (final script in migrationScripts) {
          await txn.execute(script);
        }
      });

      await db.insert(
        '__settings',
        {'key': 'schema_hash', 'value': currentSchemaHash},
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }

    await operationStore.init(db);

    // Get or create the persistent HLC node ID
    String? nodeId;
    final resultHlcNodeId = await db.query(
      '__settings',
      where: 'key = ?',
      whereArgs: ['hlc_node_id'],
    );
    if (resultHlcNodeId.isNotEmpty) {
      nodeId = resultHlcNodeId.first['value'] as String?;
    }
    if (nodeId == null) {
      nodeId = Uuid().v4();
      await db.insert('__settings', {
        'key': 'hlc_node_id',
        'value': nodeId,
      });
    }

    final hlcClock = HlcClock(nodeId: nodeId);

    return DeclarativeDatabase._internal(
      db,
      schema,
      operationStore,
      hlcClock,
    );
  }

  static Future<void> _createSystemTables(sqflite.DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS __settings (key TEXT PRIMARY KEY, value TEXT)',
    );
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
        _hlcClock,
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
    final tableSchema = _schema.tables.firstWhere((t) => t.name == table);
    final lwwColumns =
        tableSchema.columns.where((c) => c.isLww).map((c) => c.name).toSet();

    final valuesToInsert = Map<String, dynamic>.from(values);
    final now = _hlcClock.now();

    // Add system columns
    valuesToInsert['system_id'] = Uuid().v4();
    valuesToInsert['system_created_at'] = now.toString();
    valuesToInsert['system_version'] = now.toString();

    // Generate HLC timestamps for LWW columns
    if (lwwColumns.isNotEmpty) {
      for (final colName in values.keys) {
        if (lwwColumns.contains(colName)) {
          valuesToInsert['${colName}__hlc'] = now.toString();
        }
      }
    }

    final id = await _executor.insert(
      table,
      valuesToInsert,
      conflictAlgorithm: conflictAlgorithm,
    );
    if (logOperation) {
      final pk = tableSchema.keys.firstWhere((k) => k.isPrimary);
      final rowId = _getRowId(pk.columns, valuesToInsert);

      await _operationStore.add(Operation(
        tableName: table,
        rowId: rowId,
        type: OperationType.insert,
        data: valuesToInsert,
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
    required List<dynamic> whereArgs,
    bool logOperation = true,
    sqflite.ConflictAlgorithm? conflictAlgorithm,
  }) {
    return transaction((txnDb) async {
      final tableSchema = _schema.tables.firstWhere((t) => t.name == table);
      final lwwColumns =
          tableSchema.columns.where((c) => c.isLww).map((c) => c.name).toSet();

      final valuesToUpdate = Map<String, dynamic>.from(values);
      final now = _hlcClock.now();

      // Always update system_version on every change
      valuesToUpdate['system_version'] = now.toString();

      if (lwwColumns.isNotEmpty) {
        final existingRows = await txnDb.queryTable(
          table,
          columns: [
            ...values.keys.where(lwwColumns.contains).map((c) => '${c}__hlc'),
          ],
          where: where,
          whereArgs: whereArgs,
        );

        if (existingRows.isNotEmpty) {
          final existingHlcs = existingRows.first;
          for (final colName in values.keys) {
            if (lwwColumns.contains(colName)) {
              final hlcColName = '${colName}__hlc';
              final existingHlc = existingHlcs[hlcColName] != null
                  ? Hlc.fromString(existingHlcs[hlcColName] as String)
                  : null;
              if (existingHlc == null || now.compareTo(existingHlc) > 0) {
                valuesToUpdate[hlcColName] = now.toString();
              } else {
                // The value in the database is newer, so we remove this
                // column from the update.
                valuesToUpdate.remove(colName);
              }
            }
          }
        }
      }

      if (valuesToUpdate.isEmpty ||
          (valuesToUpdate.length == 1 &&
              valuesToUpdate.containsKey('system_version') &&
              !values.containsKey('system_version'))) {
        return 0; // Nothing to update
      }

      final count = await txnDb._executor.update(
        table,
        valuesToUpdate,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );

      if (logOperation && count > 0) {
        // To keep the log simple, we log the intended data, not the final
        // merged data. The conflict resolution happens on the receiving end.
        final pk = tableSchema.keys.firstWhere((k) => k.isPrimary);
        final whereClauseParts = where.split('AND').map((s) => s.trim());
        final rowIdParts = <String, dynamic>{};
        for (final col in pk.columns) {
          final part = whereClauseParts.firstWhere(
            (p) => p.startsWith('$col = ?'),
            orElse: () => '',
          );
          if (part.isNotEmpty) {
            final index = whereClauseParts.toList().indexOf(part);
            rowIdParts[col] = whereArgs[index];
          }
        }
        final rowId = _getRowId(pk.columns, rowIdParts);

        await _operationStore.add(Operation(
          tableName: table,
          rowId: rowId,
          type: OperationType.update,
          data: values, // Log the original intended update
          timestamp: DateTime.now(),
        ));
      }

      return count;
    });
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
    await _db.transaction((txnDb) async {
      final tableSchema =
          txnDb.schema.tables.firstWhere((t) => t.name == tableName);
      final pkColumns = tableSchema.keys.firstWhere((k) => k.isPrimary).columns;
      final lwwColumns =
          tableSchema.columns.where((c) => c.isLww).map((c) => c.name).toSet();
      final systemColumns = {
        'system_id',
        'system_created_at',
        'system_version'
      };

      for (final row in data) {
        final pkValues = pkColumns.map((c) => row[c]).toList();
        final whereClause = pkColumns.map((c) => '$c = ?').join(' AND ');

        final existing = await txnDb.queryTable(
          tableName,
          where: whereClause,
          whereArgs: pkValues,
        );

        if (existing.isEmpty) {
          // Insert new row
          final valuesToInsert = Map<String, dynamic>.from(row);
          final now = txnDb._hlcClock.now();
          if (!valuesToInsert.containsKey('system_id')) {
            valuesToInsert['system_id'] = Uuid().v4();
          }
          if (!valuesToInsert.containsKey('system_created_at')) {
            valuesToInsert['system_created_at'] = now.toString();
          }
          if (!valuesToInsert.containsKey('system_version')) {
            valuesToInsert['system_version'] = now.toString();
          }

          for (final colName in lwwColumns) {
            if (valuesToInsert.containsKey(colName) &&
                !valuesToInsert.containsKey('${colName}__hlc')) {
              valuesToInsert['${colName}__hlc'] = now.toString();
            }
          }
          await txnDb.insert(tableName, valuesToInsert, logOperation: false);
        } else {
          // Update existing row, respecting LWW
          final existingRow = existing.first;
          final updateValues = <String, dynamic>{};
          final now = txnDb._hlcClock.now();

          // Always update system_version
          updateValues['system_version'] = now.toString();

          for (final entry in row.entries) {
            final colName = entry.key;
            if (pkColumns.contains(colName) || colName.endsWith('__hlc')) {
              continue;
            }

            if (lwwColumns.contains(colName)) {
              final hlcColName = '${colName}__hlc';
              final localHlcString = existingRow[hlcColName] as String?;
              final remoteHlcString = row[hlcColName] as String?;

              final localHlc = localHlcString != null
                  ? Hlc.fromString(localHlcString)
                  : null;
              final remoteHlc = remoteHlcString != null
                  ? Hlc.fromString(remoteHlcString)
                  : null;

              // Take the remote value only if local doesn't exist or remote is strictly newer
              if (remoteHlc != null &&
                  (localHlc == null || remoteHlc.compareTo(localHlc) > 0)) {
                updateValues[colName] = entry.value;
                updateValues[hlcColName] = remoteHlc.toString();
              }
              // If local is newer or they are the same, or remoteHlc is null, do nothing.
            } else if (existingRow[colName] != entry.value &&
                !systemColumns.contains(colName)) {
              // For non-LWW columns, we just take the incoming value if different
              updateValues[colName] = entry.value;
            }
          }

          if (updateValues.isNotEmpty) {
            await txnDb.update(
              tableName,
              updateValues,
              where: whereClause,
              whereArgs: pkValues,
              logOperation: false,
            );
          }
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> getOperations({
    int limit = 100,
  }) async {
    final result = await _db.rawQuery(
      'SELECT * FROM _declarative_sqlite_operations ORDER BY timestamp ASC LIMIT ?',
      [limit],
    );
    return result;
  }
}
