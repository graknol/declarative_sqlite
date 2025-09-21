import 'dart:async';

import 'package:declarative_sqlite/src/builders/query_builder.dart';
import 'package:declarative_sqlite/src/record.dart';
import 'package:declarative_sqlite/src/record_factory.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/sync/sqlite_dirty_row_store.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;
import 'package:uuid/uuid.dart';

import 'files/file_repository.dart';
import 'files/fileset.dart';
import 'files/fileset_field.dart';
import 'migration/diff_schemas.dart';
import 'migration/generate_migration_scripts.dart';
import 'migration/introspect_schema.dart';
import 'schema/schema.dart';
import 'streaming/query_stream_manager.dart';
import 'streaming/streaming_query.dart';
import 'sync/hlc.dart';
import 'sync/dirty_row_store.dart';

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

  final DirtyRowStore dirtyRowStore;

  /// The repository for storing and retrieving file content.
  final IFileRepository fileRepository;

  /// The Hybrid Logical Clock for generating timestamps.
  final HlcClock hlcClock;

  final String? transactionId;

  /// API for interacting with filesets.
  late final FileSet files;

  /// Manager for streaming queries.
  late final QueryStreamManager _streamManager;

  DeclarativeDatabase._internal(
    this._db,
    this.schema,
    this.dirtyRowStore,
    this.hlcClock,
    this.fileRepository,
  ) : transactionId = null {
    files = FileSet(this);
    _streamManager = QueryStreamManager();
  }

  DeclarativeDatabase._inTransaction(
    this._db,
    this.schema,
    this.dirtyRowStore,
    this.hlcClock,
    this.fileRepository,
    this.transactionId,
  ) {
    files = FileSet(this);
    _streamManager = QueryStreamManager();
  }

  /// Opens the database at the given [path].
  ///
  /// The [schema] is used to create and migrate the database.
  /// The [dirtyRowStore] is used to store and retrieve operations for CRDTs.
  /// The [databaseFactory] is used to open the database.
  static Future<DeclarativeDatabase> open(
    String path, {
    required sqflite.DatabaseFactory databaseFactory,
    required Schema schema,
    DirtyRowStore? dirtyRowStore,
    required IFileRepository fileRepository,
    bool isReadOnly = false,
    bool isSingleInstance = true,
  }) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        readOnly: isReadOnly,
        singleInstance: isSingleInstance,
      ),
    );

    // Migrate schema
    final liveSchemaHash = await _getSetting(db, 'schema_hash');
    final newSchemaHash = schema.toHash();
    if (newSchemaHash != liveSchemaHash) {
      final liveSchema = await introspectSchema(db);
      final changes = diffSchemas(schema, liveSchema);
      final scripts = generateMigrationScripts(changes);
      for (final script in scripts) {
        await db.execute(script);
      }
    }

    // Initialize the dirty row store
    dirtyRowStore ??= SqliteDirtyRowStore();
    await dirtyRowStore.init(db);

    // Get or create the persistent HLC node ID
    final nodeId =
        await _setSettingIfNotSet(db, 'hlc_node_id', () => Uuid().v4());

    final hlcClock = HlcClock(nodeId: nodeId);

    return DeclarativeDatabase._internal(
      db,
      schema,
      dirtyRowStore,
      hlcClock,
      fileRepository,
    );
  }

  /// Closes the database.
  Future<void> close() async {
    _streamManager.dispose();
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
  Future<List<Map<String, Object?>>> query(
      void Function(QueryBuilder) onBuild) {
    final builder = QueryBuilder();
    onBuild(builder);
    return queryWith(builder);
  }

  /// Executes a query built with a [QueryBuilder].
  Future<List<Map<String, Object?>>> queryWith(QueryBuilder builder) async {
    final (sql, params) = builder.build();
    final rawResults = await rawQuery(sql, params);
    
    // Apply fileset transformation if we have table context
    final tableName = builder.tableName;
    if (tableName != null) {
      return _transformFilesetColumns(tableName, rawResults);
    }
    
    return rawResults;
  }

  /// Creates a streaming query that emits new results whenever the underlying data changes.
  /// 
  /// The [onBuild] callback is used to configure the query using a [QueryBuilder].
  /// The [mapper] function converts raw database rows to typed objects.
  /// 
  /// Returns a [Stream] that emits a list of results whenever the query result changes.
  /// The stream will emit an initial result when subscribed to, and then emit new results
  /// whenever insert, update, delete, or bulkLoad operations affect the query dependencies.
  /// 
  /// Example:
  /// ```dart
  /// final usersStream = db.stream<User>(
  ///   (q) => q.from('users').where(col('age').gt(18)),
  ///   (row) => User.fromMap(row),
  /// );
  /// 
  /// usersStream.listen((users) {
  ///   print('Users updated: ${users.length}');
  /// });
  /// ```
  Stream<List<T>> stream<T>(
    void Function(QueryBuilder) onBuild,
    T Function(Map<String, Object?>) mapper,
  ) {
    final builder = QueryBuilder();
    onBuild(builder);
    return streamWith(builder, mapper);
  }

  /// Creates a streaming query using an existing [QueryBuilder].
  /// 
  /// See [stream] for more details.
  Stream<List<T>> streamWith<T>(
    QueryBuilder builder,
    T Function(Map<String, Object?>) mapper,
  ) {
    final queryId = Uuid().v4();
    final streamingQuery = StreamingQuery.create<T>(
      id: queryId,
      builder: builder,
      database: this,
      mapper: mapper,
    );

    _streamManager.register(streamingQuery);
    
    // Clean up when stream is disposed
    streamingQuery.stream.listen(
      null,
      onDone: () => _streamManager.unregister(queryId),
    );

    return streamingQuery.stream;
  }

  /// Executes a query built with a [QueryBuilder] and returns typed DbRecord objects.
  /// This provides a more convenient API with automatic type conversion and
  /// setter functionality for easy updates.
  Future<List<DbRecord>> queryRecords(
      void Function(QueryBuilder) onBuild) async {
    final builder = QueryBuilder();
    onBuild(builder);
    return queryRecordsWith(builder);
  }

  /// Executes a query built with a [QueryBuilder] and returns typed DbRecord objects.
  Future<List<DbRecord>> queryRecordsWith(QueryBuilder builder) async {
    final results = await queryWith(builder);
    final tableName = builder.tableName;
    
    if (tableName == null) {
      throw ArgumentError('QueryBuilder must specify a table to return DbRecord objects');
    }
    
    return RecordFactory.fromMapList(results, tableName, this);
  }

  /// Queries a table and returns typed DbRecord objects.
  /// This is similar to queryTable but returns DbRecord objects instead of Maps.
  Future<List<DbRecord>> queryTableRecords(
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
    final results = await queryTable(
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
    
    return RecordFactory.fromMapList(results, table, this);
  }

  /// Creates a streaming query that returns typed DbRecord objects.
  /// 
  /// Example:
  /// ```dart
  /// final usersStream = db.streamRecords(
  ///   (q) => q.from('users').where(col('age').gt(18)),
  /// );
  /// 
  /// usersStream.listen((users) {
  ///   for (final user in users) {
  ///     print('User: ${user.getValue<String>('name')}');
  ///     // or with dynamic access: print('User: ${user.name}');
  ///   }
  /// });
  /// ```
  Stream<List<DbRecord>> streamRecords(
    void Function(QueryBuilder) onBuild,
  ) {
    final builder = QueryBuilder();
    onBuild(builder);
    return streamRecordsWith(builder);
  }

  /// Creates a streaming query using an existing [QueryBuilder] that returns DbRecord objects.
  Stream<List<DbRecord>> streamRecordsWith(QueryBuilder builder) {
    final tableName = builder.tableName;
    if (tableName == null) {
      throw ArgumentError('QueryBuilder must specify a table to return DbRecord objects');
    }
    
    return streamWith(
      builder,
      (row) => RecordFactory.fromMap(row, tableName, this),
    );
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
          dirtyRowStore,
          hlcClock,
          fileRepository,
          txnId,
        );
        return await action(db);
      },
      exclusive: exclusive,
    );
  }

  /// Inserts a row into the given [tableName].
  ///
  /// Returns the System ID of the last inserted row.
  Future<String> insert(String tableName, Map<String, Object?> values) async {
    final now = hlcClock.now();
    final systemId = await _insert(tableName, values, now);
    await dirtyRowStore.add(tableName, systemId, now);
    
    // Notify streaming queries of the change
    await _streamManager.notifyTableChanged(tableName);
    
    return systemId;
  }

  Future<String> _insert(
      String tableName, Map<String, Object?> values, Hlc hlc) async {
    final tableDef = _getTableDefinition(tableName);

    // Convert FilesetField values to database strings
    final convertedValues = _convertFilesetFieldsToValues(tableName, values);
    
    final valuesToInsert = {...convertedValues};
    valuesToInsert['system_version'] = hlc.toString();
    if (valuesToInsert['system_id'] == null) {
      valuesToInsert['system_id'] = Uuid().v4();
    }
    if (valuesToInsert['system_created_at'] == null) {
      valuesToInsert['system_created_at'] = hlc.toString();
    }

    for (final col in tableDef.columns) {
      if (col.isLww) {
        valuesToInsert['${col.name}__hlc'] = hlc.toString();
      }
    }

    await _db.insert(tableName, valuesToInsert);

    return valuesToInsert['system_id']! as String;
  }

  /// Updates rows in the given [tableName].
  ///
  /// The [values] are the new values for the rows.
  /// The [where] and [whereArgs] are used to filter the rows to update.
  ///
  /// Returns the number of rows updated.
  Future<int> update(
    String tableName,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    // We need to get the system_ids of the rows being updated so we can
    // mark them as dirty.
    final rowsToUpdate = await queryTable(
      tableName,
      columns: ['system_id'],
      where: where,
      whereArgs: whereArgs,
    );

    final now = hlcClock.now();
    final result = await _update(
      tableName,
      values,
      now,
      where: where,
      whereArgs: whereArgs,
    );

    for (final row in rowsToUpdate) {
      await dirtyRowStore.add(tableName, row['system_id']! as String, now);
    }

    // Notify streaming queries of the change
    await _streamManager.notifyTableChanged(tableName);

    return result;
  }

  Future<int> _update(
    String tableName,
    Map<String, Object?> values,
    Hlc hlc, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final tableDef = _getTableDefinition(tableName);

    // Convert FilesetField values to database strings
    final convertedValues = _convertFilesetFieldsToValues(tableName, values);

    final lwwColumns =
        tableDef.columns.where((c) => c.isLww).map((c) => c.name);

    final valuesToUpdate = {...convertedValues};
    valuesToUpdate['system_version'] = hlc.toString();

    if (lwwColumns.isNotEmpty) {
      // We need to check the HLCs of the existing rows to see if we can
      // update them.
      final existingRows = await queryTable(
        tableName,
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
                ? Hlc.parse(existingHlcs[hlcColName] as String)
                : null;
            if (existingHlc == null || hlc.compareTo(existingHlc) > 0) {
              valuesToUpdate[hlcColName] = hlc.toString();
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

    return _db.update(
      tableName,
      valuesToUpdate,
      where: where,
      whereArgs: whereArgs,
    );
  }

  Table _getTableDefinition(String tableName) {
    return schema.tables.firstWhere(
      (t) => t.name == tableName,
      orElse: () =>
          throw ArgumentError('Table not found in schema: $tableName'),
    );
  }

  /// Deletes rows from the given [tableName].
  ///
  /// The [where] and [whereArgs] are used to filter the rows to delete.
  ///
  /// Returns the number of rows deleted.
  Future<int> delete(
    String tableName, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    // Make sure the table exists or throw an exception
    final _ = _getTableDefinition(tableName);

    final now = hlcClock.now();

    final rowsToDelete = await queryTable(
      tableName,
      columns: ['system_id'],
      where: where,
      whereArgs: whereArgs,
    );

    final result = await _db.delete(
      tableName,
      where: where,
      whereArgs: whereArgs,
    );

    for (final row in rowsToDelete) {
      await dirtyRowStore.add(tableName, row['system_id']! as String, now);
    }

    // Notify streaming queries of the change
    await _streamManager.notifyTableChanged(tableName);

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
  }) async {
    final rawResults = await _db.query(
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
    
    return _transformFilesetColumns(table, rawResults);
  }

  /// Transforms raw query results by converting fileset columns to FilesetField objects.
  List<Map<String, Object?>> _transformFilesetColumns(
    String tableName,
    List<Map<String, Object?>> rawResults,
  ) {
    if (rawResults.isEmpty) return rawResults;
    
    // Get table definition to identify fileset columns
    final tableDef = _getTableDefinition(tableName);
    final filesetColumns = tableDef.columns
        .where((col) => col.logicalType == 'fileset')
        .map((col) => col.name)
        .toSet();
    
    if (filesetColumns.isEmpty) return rawResults;
    
    // Transform each row
    return rawResults.map((row) {
      final transformedRow = <String, Object?>{...row};
      
      for (final columnName in filesetColumns) {
        if (transformedRow.containsKey(columnName)) {
          final value = transformedRow[columnName];
          transformedRow[columnName] = _createFilesetField(value);
        }
      }
      
      return transformedRow;
    }).toList();
  }

  /// Creates a FilesetField from a database value.
  Object? _createFilesetField(Object? value) {
    if (value == null) return null;
    return FilesetField.fromDatabaseValue(value, this);
  }

  /// Converts FilesetField values back to database strings before storing.
  Map<String, Object?> _convertFilesetFieldsToValues(
    String tableName,
    Map<String, Object?> values,
  ) {
    final tableDef = _getTableDefinition(tableName);
    final filesetColumns = tableDef.columns
        .where((col) => col.logicalType == 'fileset')
        .map((col) => col.name)
        .toSet();
    
    if (filesetColumns.isEmpty) return values;
    
    final convertedValues = <String, Object?>{...values};
    
    for (final columnName in filesetColumns) {
      if (convertedValues.containsKey(columnName)) {
        final value = convertedValues[columnName];
        if (value is FilesetField) {
          convertedValues[columnName] = value.toDatabaseValue();
        }
      }
    }
    
    return convertedValues;
  }

  /// Bulk loads data into a table, performing an "upsert" operation.
  ///
  /// This method is designed for loading data from a sync source. It respects
  /// LWW (Last-Write-Wins) semantics for columns marked as such.
  ///
  /// For each row in [rows]:
  /// - If a local row with the same `system_id` exists, it's an UPDATE.
  ///   - LWW columns are only updated if the incoming HLC is newer.
  ///   - Regular columns are always updated.
  /// - If no local row exists, it's an INSERT.
  ///
  /// Rows processed by this method are NOT marked as dirty.
  Future<void> bulkLoad(
      String tableName, List<Map<String, Object?>> rows) async {
    final tableDef = _getTableDefinition(tableName);
    final pkColumns = tableDef.keys
        .where((k) => k.isPrimary)
        .expand((k) => k.columns)
        .toSet();
    final lwwColumns =
        tableDef.columns.where((c) => c.isLww).map((c) => c.name).toSet();

    await transaction((db) async {
      for (final row in rows) {
        final systemId = row['system_id'] as String?;
        if (systemId == null) continue;

        final existing = await db.queryTable(
          tableName,
          where: 'system_id = ?',
          whereArgs: [systemId],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          // UPDATE logic
          final existingRow = existing.first;
          final valuesToUpdate = <String, Object?>{};
          final now = hlcClock.now();

          for (final entry in row.entries) {
            final colName = entry.key;
            if (pkColumns.contains(colName) || colName.endsWith('__hlc')) {
              continue;
            }

            if (lwwColumns.contains(colName)) {
              final hlcColName = '${colName}__hlc';
              final remoteHlcString = row[hlcColName] as String?;

              if (remoteHlcString != null) {
                // If HLC is provided, do a proper LWW comparison.
                final localHlcString = existingRow[hlcColName] as String?;
                final localHlc =
                    localHlcString != null ? Hlc.parse(localHlcString) : null;
                final remoteHlc = Hlc.parse(remoteHlcString);

                if (localHlc == null || remoteHlc.compareTo(localHlc) > 0) {
                  valuesToUpdate[colName] = entry.value;
                  valuesToUpdate[hlcColName] = remoteHlc.toString();
                }
              } else {
                // If no HLC is provided, the server value wins (non-LWW update).
                valuesToUpdate[colName] = entry.value;
              }
            } else {
              // Regular column, always update.
              valuesToUpdate[colName] = entry.value;
            }
          }

          if (valuesToUpdate.isNotEmpty) {
            await db._update(
              tableName,
              valuesToUpdate,
              now,
              where: 'system_id = ?',
              whereArgs: [systemId],
            );
          }
        } else {
          // INSERT logic
          await db._insert(tableName, row, hlcClock.now());
        }
      }
    });
    
    // Notify streaming queries of the change
    await _streamManager.notifyTableChanged(tableName);
  }

  static Future<bool> _removeSetting(
    sqflite.DatabaseExecutor db,
    String key,
  ) async {
    final deleteCount = await db.delete(
      '__settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return deleteCount > 0;
  }

  static Future<String> _setSettingIfNotSet(
    sqflite.DatabaseExecutor db,
    String key,
    String Function() defaultFactory,
  ) async {
    var result = await _getSetting(db, key);
    result ??= await _setSetting(db, key, defaultFactory());
    return result;
  }

  static Future<String> _setSetting(
    sqflite.DatabaseExecutor db,
    String key,
    String value,
  ) async {
    await db.insert(
      '__settings',
      {
        'key': key,
        'value': value,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
    return value;
  }

  static Future<String?> _getSettingOrDefault(
    sqflite.DatabaseExecutor db,
    String key,
    String Function() defaultFactory,
  ) async {
    return (await _getSetting(db, key)) ?? defaultFactory();
  }

  static Future<String?> _getSetting(
    sqflite.DatabaseExecutor db,
    String key,
  ) async {
    try {
      final result = await db.query('__settings',
          where: 'key = ?', whereArgs: [key], limit: 1, columns: ['value']);
      if (result.isNotEmpty) {
        return result.first['value'] as String?;
      }
    } on Exception {
      // Ignore any errors, most likely due to missing table,
      // in which case, there's nothing to do but to return null
    }
    return null;
  }
}
