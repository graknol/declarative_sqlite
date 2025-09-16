import 'dart:async';

import 'package:declarative_sqlite/src/builders/query_builder.dart';
import 'package:meta/meta.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;
import 'package:uuid/uuid.dart';

import 'files/fileset.dart';
import 'files/file_repository.dart';
import 'migration/diff_schemas.dart';
import 'migration/generate_migration_scripts.dart';
import 'migration/introspect_schema.dart';
import 'schema/schema.dart';
import 'sync/hlc.dart';
import 'sync/operation_store.dart';

/// A declarative SQLite database.
class DeclarativeDatabase {
  /// The underlying sqflite database.
  ///
  /// This is exposed for advanced use cases, but it's recommended to use the
  /// declarative API as much as possible.
  sqflite.DatabaseExecutor get db => _db;
  final sqflite.DatabaseExecutor _db;

  /// The schema for the database.
  final Schema schema;

  final OperationStore operationStore;

  /// The repository for storing and retrieving file content.
  final IFileRepository fileRepository;

  /// The Hybrid Logical Clock for generating timestamps.
  final HlcClock hlcClock;

  final String? transactionId;

  /// API for interacting with filesets.
  late final FileSet files;

  DeclarativeDatabase._internal(
    this._db,
    this.schema,
    this.operationStore,
    this.hlcClock,
    this.fileRepository,
  ) : transactionId = null {
    files = FileSet(this);
  }

  DeclarativeDatabase._inTransaction(
    this._db,
    this.schema,
    this.operationStore,
    this.hlcClock,
    this.fileRepository,
    this.transactionId,
  ) {
    files = FileSet(this);
  }

  /// Opens the database at the given [path].
  ///
  /// The [schema] is used to create and migrate the database.
  /// The [operationStore] is used to store and retrieve operations for CRDTs.
  /// The [databaseFactory] is used to open the database.
  static Future<DeclarativeDatabase> open(
    String path, {
    required sqflite.DatabaseFactory databaseFactory,
    required Schema schema,
    required OperationStore operationStore,
    required IFileRepository fileRepository,
    bool isReadOnly = false,
    bool isSingleInstance = true,
  }) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        readOnly: isReadOnly,
        singleInstance: isSingleInstance,
        version: schema.version,
        onCreate: (db, version) async {
          await _createSystemTables(db);
          await _createSchema(db, schema);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _createSystemTables(db);
          final liveSchema = await introspectSchema(db);
          final changes = diffSchemas(schema, liveSchema);
          final scripts = generateMigrationScripts(changes);
          for (final script in scripts) {
            await db.execute(script);
          }
        },
      ),
    );

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
      fileRepository,
    );
  }

  static Future<void> _createSchema(
      sqflite.DatabaseExecutor db, Schema schema) async {
    for (final table in schema.tables) {
      final columnDefs = table.columns.map((c) => c.toSql()).join(', ');

      final keyDefs = <String>[];
      for (final key in table.keys) {
        if (key.isPrimary) {
          keyDefs.add('PRIMARY KEY (${key.columns.join(', ')})');
        }
      }

      final allDefs = [columnDefs, ...keyDefs].join(', ');
      await db.execute('CREATE TABLE ${table.name} ($allDefs)');

      for (final key in table.keys) {
        if (!key.isPrimary) {
          final indexName = 'IX_${table.name}_${key.columns.join('_')}';
          await db.execute(
              'CREATE INDEX IF NOT EXISTS $indexName ON ${table.name} (${key.columns.join(', ')})');
        }
      }
    }
  }

  static Future<void> _createSystemTables(sqflite.DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS __settings (key TEXT PRIMARY KEY, value TEXT)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS __dirty_rows (
        table_name TEXT NOT NULL,
        row_id TEXT NOT NULL,
        hlc TEXT NOT NULL,
        PRIMARY KEY (table_name, row_id)
      )
    ''');
  }

  /// Closes the database.
  Future<void> close() async {
    if (_db is sqflite.Database) {
      return _db.close();
    }
  }

  /// Executes a raw SQL query and returns a list of the results.
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _db.rawQuery(sql, arguments);
  }

  /// Executes a raw SQL statement and returns the number of changes.
  Future<int> rawUpdate(
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _db.rawUpdate(sql, arguments);
  }

  /// Executes a raw SQL INSERT query and returns the last inserted row ID.
  Future<int> rawInsert(
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _db.rawInsert(sql, arguments);
  }

  /// Executes a raw SQL DELETE query and returns the number of changes.
  Future<int> rawDelete(
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _db.rawDelete(sql, arguments);
  }

  /// Executes a query built with a [QueryBuilder].
  /// This is a cleaner way of composing the query,
  /// rather than having to create the [QueryBuilder]
  /// object yourself.
  Future<List<Map<String, Object?>>> query(void Function(QueryBuilder) onBuild) {
    final builder = QueryBuilder();
    onBuild(builder);
    return queryWith(builder);
  }

  /// Executes a query built with a [QueryBuilder].
  Future<List<Map<String, Object?>>> queryWith(QueryBuilder builder) {
    final (sql, params) = builder.build();
    return rawQuery(sql, params);
  }

  /// Creates a transaction and runs the given [action] in it.
  ///
  /// The [action] is provided with a new [DeclarativeDatabase] instance that
  /// is bound to the transaction.
  Future<T> transaction<T>(
    Future<T> Function(DeclarativeDatabase txn) action, {
    bool? exclusive,
  }) async {
    if (_db is! sqflite.Database) {
      throw StateError('Cannot start a transaction within a transaction.');
    }
    final txnId = Uuid().v4();
    return _db.transaction(
      (txn) async {
        final db = DeclarativeDatabase._inTransaction(
          txn,
          schema,
          operationStore,
          hlcClock,
          fileRepository,
          txnId,
        );
        return await action(db);
      },
      exclusive: exclusive,
    );
  }

  /// Inserts a row into the given [table].
  ///
  /// Returns the ID of the last inserted row.
  Future<int> insert(String table, Map<String, Object?> values) async {
    final tableDef = schema.tables.firstWhere((t) => t.name == table,
        orElse: () => throw ArgumentError('Table not found in schema: $table'));

    final now = hlcClock.now();
    final valuesToInsert = {...values};
    valuesToInsert['system_version'] = now.toString();
    if (valuesToInsert['system_id'] == null) {
      valuesToInsert['system_id'] = Uuid().v4();
    }
    if (valuesToInsert['system_created_at'] == null) {
      valuesToInsert['system_created_at'] = now.toString();
    }

    for (final col in tableDef.columns) {
      if (col.isLww) {
        valuesToInsert['${col.name}__hlc'] = now.toString();
      }
    }

    final result = await _db.insert(table, valuesToInsert);
    await _markDirty(table, valuesToInsert['system_id']! as String, now);
    return result;
  }

  /// Updates rows in the given [table].
  ///
  /// The [values] are the new values for the rows.
  /// The [where] and [whereArgs] are used to filter the rows to update.
  ///
  /// Returns the number of rows updated.
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final tableDef = schema.tables.firstWhere((t) => t.name == table,
        orElse: () => throw ArgumentError('Table not found in schema: $table'));

    final lwwColumns =
        tableDef.columns.where((c) => c.isLww).map((c) => c.name);

    final now = hlcClock.now();
    final valuesToUpdate = {...values};
    valuesToUpdate['system_version'] = now.toString();

    if (lwwColumns.isNotEmpty) {
      // We need to check the HLCs of the existing rows to see if we can
      // update them.
      final existingRows = await queryTable(
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

    if (valuesToUpdate.length == 1 &&
        valuesToUpdate.containsKey('system_version')) {
      // Nothing to update except the system version, so we can skip this.
      return 0;
    }

    // We need to get the system_ids of the rows being updated so we can
    // mark them as dirty.
    final rowsToUpdate = await queryTable(
      table,
      columns: ['system_id'],
      where: where,
      whereArgs: whereArgs,
    );

    final result = await _db.update(
      table,
      valuesToUpdate,
      where: where,
      whereArgs: whereArgs,
    );

    for (final row in rowsToUpdate) {
      await _markDirty(table, row['system_id']! as String, now);
    }

    return result;
  }

  /// Deletes rows from the given [table].
  ///
  /// The [where] and [whereArgs] are used to filter the rows to delete.
  ///
  /// Returns the number of rows deleted.
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    // To support CRDTs, we need to get the system_id of the rows being
    // deleted so we can log the delete operation.
    final rowsToDelete = await queryTable(
      table,
      columns: ['system_id'],
      where: where,
      whereArgs: whereArgs,
    );

    final result = await _db.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );

    final now = hlcClock.now();
    for (final row in rowsToDelete) {
      await _markDirty(table, row['system_id']! as String, now);
    }

    return result;
  }

  /// Queries the given [table] and returns a list of the results.
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
  }) {
    return _db.query(
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

  Future<void> _markDirty(String tableName, String rowId, Hlc hlc) async {
    await _db.rawInsert('''
      INSERT OR REPLACE INTO __dirty_rows (table_name, row_id, hlc)
      VALUES (?, ?, ?)
    ''', [tableName, rowId, hlc.toString()]);
  }
}
