import 'dart:async';
import 'dart:developer' as developer;

import 'package:declarative_sqlite/src/builders/query_builder.dart';
import 'package:declarative_sqlite/src/builders/where_clause.dart';
import 'package:declarative_sqlite/src/exceptions/db_exception_wrapper.dart';
import 'package:declarative_sqlite/src/db_record.dart';
import 'package:declarative_sqlite/src/record_factory.dart';
import 'package:declarative_sqlite/src/record_map_factory_registry.dart';
import 'package:declarative_sqlite/src/schema/db_column.dart';
import 'package:declarative_sqlite/src/schema/db_table.dart';
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
import 'sync/dirty_row.dart';

/// Strategy for handling constraint violations during bulk load operations
enum ConstraintViolationStrategy {
  /// Throw the original exception (default behavior)
  throwException,
  
  /// Silently skip the problematic row and continue processing
  skip,
}

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

  final DirtyRowStore? dirtyRowStore;

  /// The query stream manager for this database instance
  QueryStreamManager get streamManager => _streamManager;

  /// A stream that emits dirty rows as they are added to the dirty row store.
  /// 
  /// This stream allows you to reactively respond to database changes instead
  /// of polling for dirty rows. Each emission contains the DirtyRow that was
  /// just added to the store.
  /// 
  /// Returns null if no dirty row store is configured.
  /// 
  /// Example usage:
  /// ```dart
  /// database.onDirtyRowAdded?.listen((dirtyRow) {
  ///   print('New dirty row: ${dirtyRow.tableName} ${dirtyRow.rowId}');
  ///   // Trigger sync logic here
  ///   syncService.sync();
  /// });
  /// ```
  Stream<DirtyRow>? get onDirtyRowAdded => dirtyRowStore?.onRowAdded;

  /// The repository for storing and retrieving file content.
  final IFileRepository fileRepository;

  /// The Hybrid Logical Clock for generating timestamps.
  final HlcClock hlcClock;

  /// API for interacting with filesets.
  late final FileSet files;

  /// Manager for streaming queries.
  late final QueryStreamManager _streamManager;

  final Map<String, DbRecord> _recordCache = {};

  DeclarativeDatabase._internal(
    this._db,
    this.schema,
    this.dirtyRowStore,
    this.hlcClock,
    this.fileRepository,
  ) {
    files = FileSet(this);
    _streamManager = QueryStreamManager();
  }

  // Cache and registry methods
  void registerRecord(DbRecord record) {
    final systemId = record.systemId;
    if (systemId != null) {
      _recordCache[systemId] = record;
    }
  }

  DbRecord? getRecordFromCache(String systemId) {
    return _recordCache[systemId];
  }

  /// Opens the database at the given [path].
  ///
  /// The [schema] is used to create and migrate the database.
  /// The [dirtyRowStore] is used to store and retrieve operations for CRDTs.
  /// The [databaseFactory] is used to open the database.
  /// 
  /// If [recreateDatabase] is true, the existing database file will be deleted
  /// before opening. This is useful for testing and demo data initialization.
  /// Defaults to false for production safety.
  /// 
  /// **SAFETY**: [recreateDatabase] only works in debug mode to prevent
  /// accidental data loss in production. In release mode, this parameter
  /// is ignored and an assertion error is thrown if set to true.
  static Future<DeclarativeDatabase> open(
    String path, {
    required sqflite.DatabaseFactory databaseFactory,
    required Schema schema,
    DirtyRowStore? dirtyRowStore,
    required IFileRepository fileRepository,
    bool isReadOnly = false,
    bool isSingleInstance = true,
    bool recreateDatabase = false,
  }) async {
    return await DbExceptionWrapper.wrapConnection(() async {
      // Safety check: recreateDatabase only works in debug mode
      assert(() {
        if (recreateDatabase && !isReadOnly) {
          // This assertion will only be active in debug mode
          return true;
        }
        return true;
      }(), 'recreateDatabase can only be used in debug mode for safety');
      
      // Delete existing database if recreation is requested
      if (recreateDatabase && !isReadOnly) {
        // Double check: only proceed if assertions are enabled (debug mode)
        var debugMode = false;
        assert(() {
          debugMode = true;
          return true;
        }());
        
        if (debugMode) {
          try {
            await databaseFactory.deleteDatabase(path);
          } catch (e) {
            // Ignore errors if database doesn't exist
          }
        } else {
          throw StateError(
            'recreateDatabase=true is not allowed in production/release mode. '
            'This is a safety measure to prevent accidental data loss.'
          );
        }
      }
      
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
        developer.log('🔄 Schema hash mismatch detected. Starting migration...', name: 'Migration');
        developer.log('  Current hash: $liveSchemaHash', name: 'Migration');
        developer.log('  Target hash:  $newSchemaHash', name: 'Migration');
        
        final liveSchema = await introspectSchema(db);
        developer.log('📊 Introspected current schema: ${liveSchema.tables.length} tables, ${liveSchema.views.length} views', name: 'Migration');
        
        final changes = diffSchemas(schema, liveSchema);
        developer.log('🔍 Schema diff complete: ${changes.length} changes identified', name: 'Migration');
        
        final scripts = generateMigrationScripts(changes);
        developer.log('⚡ Executing ${scripts.length} migration scripts...', name: 'Migration');
        
        for (int i = 0; i < scripts.length; i++) {
          final script = scripts[i];
          developer.log('🔧 Executing script ${i + 1}/${scripts.length}: ${script.length > 100 ? '${script.substring(0, 100)}...' : script}', name: 'Migration');
          try {
            await db.execute(script);
            developer.log('  ✅ Script ${i + 1} executed successfully', name: 'Migration');
          } catch (e) {
            developer.log('  ❌ Script ${i + 1} failed: $e', name: 'Migration');
            rethrow;
          }
        }
        
        await _setSetting(db, 'schema_hash', newSchemaHash);
        developer.log('✅ Migration completed successfully! New schema hash: $newSchemaHash', name: 'Migration');
      } else {
        developer.log('✨ Schema is up to date (hash: $liveSchemaHash)', name: 'Migration');
      }

      // Initialize the dirty row store
      dirtyRowStore ??= SqliteDirtyRowStore();
      await dirtyRowStore?.init(db);

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
    });
  }

  /// Closes the database.
  Future<void> close() async {
    await _streamManager.dispose();
    await dirtyRowStore?.dispose();
    if (_db is sqflite.Database) {
      await _db.close();
    }
  }

  /// Executes a raw SQL statement.
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await _db.execute(sql, arguments);
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

  // Helper and utility methods
  
  DbTable _getTableDefinition(String tableName) {
    return schema.tables.firstWhere(
      (t) => t.name == tableName,
      orElse: () =>
          throw ArgumentError('Table not found in schema: $tableName'),
    );
  }

  /// Converts a value for database storage using the same logic as DbRecord.setValue
  Object? _serializeValueForColumn(Object? value, DbColumn column) {
    if (value == null) return null;
    
    switch (column.logicalType) {
      case 'text':
      case 'guid':
      case 'integer':
      case 'real':
        return value;
      case 'date':
        if (value is DateTime) {
          return value.toIso8601String();
        } else if (value is String) {
          return value; // Assume already serialized
        } else {
          return value.toString();
        }
      case 'fileset':
        if (value is FilesetField) {
          return value.toDatabaseValue();
        }
        return value;
      default:
        return value;
    }
  }

  /// Serializes all values in a map according to their column definitions
  Map<String, Object?> _serializeValuesForTable(String tableName, Map<String, Object?> values) {
    final tableDef = _getTableDefinition(tableName);
    final serializedValues = <String, Object?>{};
    
    for (final entry in values.entries) {
      final columnName = entry.key;
      final value = entry.value;
      
      // Find the column definition
      final column = tableDef.columns.where((col) => col.name == columnName).firstOrNull;
      
      if (column != null) {
        // Serialize using column definition
        serializedValues[columnName] = _serializeValueForColumn(value, column);
      } else {
        // Column not found in schema - pass through as-is (might be system column)
        serializedValues[columnName] = value;
      }
    }
    
    return serializedValues;
  }

  /// Applies default values for columns that are missing from the provided values map
  /// or have null values when the column doesn't allow nulls
  Map<String, Object?> _applyDefaultValues(String tableName, Map<String, Object?> values) {
    final tableDef = _getTableDefinition(tableName);
    final valuesWithDefaults = <String, Object?>{...values};
    
    // Generate default values for missing columns or null values in non-null columns
    for (final col in tableDef.columns) {
      // Skip system columns - they're handled separately
      if (col.name.startsWith('system_')) continue;
      
      final hasValue = valuesWithDefaults.containsKey(col.name);
      final currentValue = valuesWithDefaults[col.name];
      final isNullValue = currentValue == null;
      
      // Apply default if:
      // 1. Column value is not provided, OR
      // 2. Column exists but is null and column doesn't allow nulls
      final shouldApplyDefault = !hasValue || (hasValue && isNullValue && col.isNotNull);
      
      if (shouldApplyDefault) {
        final defaultValue = col.getDefaultValue();
        if (defaultValue != null) {
          // Apply the same serialization logic as DbRecord.setValue
          final serializedValue = _serializeValueForColumn(defaultValue, col);
          valuesWithDefaults[col.name] = serializedValue;
        }
      }
    }
    
    return valuesWithDefaults;
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

  /// Validates that a query result meets the requirements for forUpdate
  void _validateForUpdateQuery(
      List<Map<String, Object?>> results, String updateTableName) {
    // Check that the update table exists in the schema
    schema.userTables.firstWhere(
      (table) => table.name == updateTableName,
      orElse: () =>
          throw ArgumentError('Update table $updateTableName not found in schema'),
    );

    if (results.isEmpty) return; // No results to validate

    final firstResult = results.first;

    // Verify that system_id is present
    if (!firstResult.containsKey('system_id') ||
        firstResult['system_id'] == null) {
      throw StateError(
          'Query with forUpdate(\'$updateTableName\') must include system_id column from the target table');
    }

    // Verify that system_version is present
    if (!firstResult.containsKey('system_version') ||
        firstResult['system_version'] == null) {
      throw StateError(
          'Query with forUpdate(\'$updateTableName\') must include system_version column from the target table');
    }
  }

  /// Determines if a QueryBuilder represents a simple table query (CRUD-enabled)
  /// vs a complex query or view query (read-only by default).
  ///
  /// A simple table query is one that:
  /// - Queries directly from a table (not a view)
  /// - Has no complex joins, subqueries, or aggregations
  /// - Can be safely updated via system_id
  bool _isSimpleTableQuery(QueryBuilder builder) {
    final tableName = builder.tableName;
    if (tableName == null) return false;

    // Check if the table name refers to an actual table (not a view)
    final isActualTable =
        schema.userTables.any((table) => table.name == tableName);
    if (!isActualTable) return false;

    // For now, we'll consider any direct table reference as "simple"
    // This could be enhanced to check for complex joins, aggregations, etc.
    // based on the QueryBuilder structure
    return true;
  }

  // Query methods (read operations)

  /// Executes a query built with a [QueryBuilder] and returns raw Map objects.
  ///
  /// This is a lower-level method. Most code should use query() to get
  /// typed DbRecord objects instead of raw maps.
  ///
  /// Example:
  /// ```dart
  /// final results = await db.queryMaps((q) => q.from('users'));
  /// final userName = results.first['name'] as String; // Manual casting needed
  /// ```
  Future<List<Map<String, Object?>>> queryMaps(
      void Function(QueryBuilder) onBuild) {
    final builder = QueryBuilder();
    onBuild(builder);
    return queryMapsWith(builder);
  }

  /// Executes a query built with a [QueryBuilder] and returns raw Map results.
  Future<List<Map<String, Object?>>> queryMapsWith(QueryBuilder builder) async {
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
    return streamMapsWith(builder, mapper);
  }

  /// Creates a streaming query using an existing [QueryBuilder].
  ///
  /// See [stream] for more details.
  Stream<List<T>> streamMapsWith<T>(
    QueryBuilder builder,
    T Function(Map<String, Object?>) mapper,
  ) {
    final queryId = Uuid().v4();
    final streamingQuery = StreamingQuery.create(
      id: queryId,
      builder: builder,
      database: this,
      mapper: mapper,
    );

    // StreamingQuery will automatically register/unregister itself with the
    // QueryStreamManager when listeners subscribe/unsubscribe via _onListen/_onCancel
    return streamingQuery.stream;
  }

  /// Executes a query and returns typed DbRecord objects.
  ///
  /// This is the main query method that intelligently determines CRUD vs read-only
  /// behavior by inspecting the QueryBuilder:
  /// - Table queries (simple from('table')) → CRUD-enabled
  /// - View queries → Read-only
  /// - Complex queries with forUpdate('table') → CRUD-enabled for specified table
  ///
  /// Examples:
  /// ```dart
  /// // Table query - CRUD enabled
  /// final users = await db.query((q) => q.from('users'));
  /// users.first.setValue('name', 'Updated');
  /// await users.first.save(); // ✅ Works
  ///
  /// // View query - read-only
  /// final details = await db.query((q) => q.from('user_details_view'));
  /// details.first.setValue('name', 'Test'); // ❌ StateError
  ///
  /// // Complex query with forUpdate - CRUD enabled for target table
  /// final results = await db.query(
  ///   (q) => q.from('user_details_view').forUpdate('users')
  /// );
  /// results.first.setValue('name', 'Updated');
  /// await results.first.save(); // ✅ Updates users table
  /// ```
  Future<List<DbRecord>> query(void Function(QueryBuilder) onBuild) async {
    final builder = QueryBuilder();
    onBuild(builder);
    return queryWith(builder);
  }

  /// Executes a query built with a [QueryBuilder] and returns typed DbRecord objects.
  Future<List<DbRecord>> queryWith(QueryBuilder builder) async {
    final results = await queryMapsWith(builder);
    final tableName = builder.tableName;
    final updateTableName = builder.updateTableName;

    if (tableName == null) {
      throw ArgumentError(
          'QueryBuilder must specify a table to return DbRecord objects');
    }

    // If forUpdate was specified, validate the requirements
    if (updateTableName != null) {
      _validateForUpdateQuery(results, updateTableName);

      // Return records configured for CRUD with the specified update table
      return RecordFactory.fromMapList(results, tableName, this);
    }

    // Determine if this is a table or view query by inspecting the QueryBuilder
    final isSimpleTableQuery = _isSimpleTableQuery(builder);

    if (isSimpleTableQuery) {
      // Simple table query - CRUD enabled by default
      return RecordFactory.fromMapList(results, tableName, this);
    } else {
      // View or complex query - read-only by default
      return RecordFactory.fromMapList(results, tableName, this);
    }
  }

  /// Creates a streaming query that returns typed DbRecord objects.
  ///
  /// Like the query() method, this intelligently determines CRUD vs read-only
  /// behavior by inspecting the QueryBuilder shape.
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
  ///     user.setValue('last_seen', DateTime.now());
  ///     await user.save(); // ✅ Works for table queries
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
    final updateTableName = builder.updateTableName;

    if (tableName == null) {
      throw ArgumentError(
          'QueryBuilder must specify a table to return DbRecord objects');
    }

    return streamMapsWith(
      builder,
      (row) {
        // Validate forUpdate requirements on each emitted result
        if (updateTableName != null) {
          _validateForUpdateQuery([row], updateTableName);
          return RecordFactory.fromMap(row, tableName, this);
        }

        // Determine if this is a simple table query by inspecting the QueryBuilder
        final isSimpleTableQuery = _isSimpleTableQuery(builder);

        if (isSimpleTableQuery) {
          return RecordFactory.fromMap(row, tableName, this);
        } else {
          return RecordFactory.fromMap(row, tableName, this);
        }
      },
    );
  }

  // Typed query methods using RecordMapFactoryRegistry

  /// Executes a query and returns typed record objects using registered factories.
  ///
  /// The record type T must be registered with `RecordMapFactoryRegistry.register<T>()`.
  /// This method uses the same intelligent CRUD vs read-only detection as query().
  ///
  /// Example:
  /// ```dart
  /// // First register the factory
  /// RecordMapFactoryRegistry.register<User>(User.fromMap);
  ///
  /// // Then query with automatic typing
  /// final users = await db.queryTyped<User>((q) => q.from('users'));
  /// users.first.name = 'Updated'; // Direct property access
  /// await users.first.save(); // ✅ Works for table queries
  /// ```
  Future<List<T>> queryTyped<T extends DbRecord>(
    void Function(QueryBuilder) onBuild,
  ) async {
    final builder = QueryBuilder();
    onBuild(builder);
    return queryTypedWith<T>(builder);
  }

  /// Executes a query using an existing QueryBuilder and returns typed record objects.
  Future<List<T>> queryTypedWith<T extends DbRecord>(
      QueryBuilder builder) async {
    final results = await queryMapsWith(builder);
    final factory = RecordMapFactoryRegistry.getFactory<T>();

    return results.map((row) => factory(row, this)).toList();
  }

  /// Creates a streaming query that returns typed record objects using registered factories.
  ///
  /// Uses the same intelligent CRUD vs read-only detection as stream().
  Stream<List<T>> streamTyped<T extends DbRecord>(
    void Function(QueryBuilder) onBuild,
  ) {
    final builder = QueryBuilder();
    onBuild(builder);
    return streamTypedWith<T>(builder);
  }

  /// Creates a streaming query using an existing QueryBuilder that returns typed record objects.
  Stream<List<T>> streamTypedWith<T extends DbRecord>(QueryBuilder builder) {
    final factory = RecordMapFactoryRegistry.getFactory<T>();

    return streamMapsWith(
      builder,
      (row) => factory(row, this),
    );
  }

  /// Transactions are not supported in DeclarativeDatabase.
  ///
  /// Due to the complexity of handling edge cases like dirty row rollbacks,
  /// change notifications, and state management, transactions have been
  /// intentionally disabled. Use separate operations instead.
  Future<T> transaction<T>(
    Future<T> Function(DeclarativeDatabase txn) action, {
    bool? exclusive,
  }) async {
    throw UnsupportedError(
      'Transactions are not supported in DeclarativeDatabase. '
      'This is intentional due to complexity with dirty rows, notifications, '
      'and other edge cases. Please use separate database operations instead.'
    );
  }

  /// Inserts a row into the given [tableName].
  ///
  /// Returns the System ID of the last inserted row.
  Future<String> insert(String tableName, Map<String, Object?> values) async {
    return await DbExceptionWrapper.wrapCreate(() async {
      final now = hlcClock.now();
      
      // Serialize input values using column definitions
      final serializedValues = _serializeValuesForTable(tableName, values);
      
      final systemId = await _insert(tableName, serializedValues, now);
      // Pass only the user-provided values, not system-generated columns
      await dirtyRowStore?.add(tableName, systemId, now, true, values); // Full row for new inserts with user data

      // Notify streaming queries of the change
      await _streamManager.notifyTableChanged(tableName);

      return systemId;
    }, tableName: tableName);
  }

  Future<String> _insert(
      String tableName, Map<String, Object?> values, Hlc hlc) async {
    final tableDef = _getTableDefinition(tableName);

    // Convert FilesetField values to database strings
    final convertedValues = _convertFilesetFieldsToValues(tableName, values);

    // Apply default values for missing columns
    final valuesToInsert = _applyDefaultValues(tableName, convertedValues);
    
    // Add system columns
    valuesToInsert['system_version'] = hlc.toString();
    if (valuesToInsert['system_id'] == null) {
      valuesToInsert['system_id'] = Uuid().v4();
    }
    if (valuesToInsert['system_created_at'] == null) {
      valuesToInsert['system_created_at'] = hlc.toString();
    }
    // Mark as local origin (created by client)
    if (valuesToInsert['system_is_local_origin'] == null) {
      valuesToInsert['system_is_local_origin'] = 1;
    }

    for (final col in tableDef.columns) {
      if (col.isLww) {
        valuesToInsert['${col.name}__hlc'] = hlc.toString();
      }
    }

    await _db.insert(tableName, valuesToInsert);

    return valuesToInsert['system_id']! as String;
  }

  /// Internal method for inserting rows from server during bulkLoad
  /// Marks the row as non-local origin (came from server)
  Future<String> _insertFromServer(
      String tableName, Map<String, Object?> values, Hlc hlc) async {
    final tableDef = _getTableDefinition(tableName);

    // Convert FilesetField values to database strings
    final convertedValues = _convertFilesetFieldsToValues(tableName, values);

    // Apply default values for missing columns
    final valuesToInsert = _applyDefaultValues(tableName, convertedValues);
    
    // Add system columns
    valuesToInsert['system_version'] = hlc.toString();
    if (valuesToInsert['system_id'] == null) {
      valuesToInsert['system_id'] = Uuid().v4();
    }
    if (valuesToInsert['system_created_at'] == null) {
      valuesToInsert['system_created_at'] = hlc.toString();
    }
    // Mark as server origin (not created locally)
    valuesToInsert['system_is_local_origin'] = 0;

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
    return await DbExceptionWrapper.wrapUpdate(() async {
      final rowsToUpdate = await query(
        (q) {
          q.from(tableName).select('system_id, system_is_local_origin');
          if (where != null) {
            q.where(RawSqlWhereClause(where, whereArgs));
          }
        },
      );

      // Serialize input values using column definitions
      final serializedValues = _serializeValuesForTable(tableName, values);

      final now = hlcClock.now();
      final result = await _update(
        tableName,
        serializedValues,
        now,
        where: where,
        whereArgs: whereArgs,
      );

      if (result > 0) {
        for (final row in rowsToUpdate) {
          final isLocalOrigin = row.getValue<int>('system_is_local_origin') == 1;
          // Pass only the user-provided values, not system-generated columns
          await dirtyRowStore?.add(
              tableName, row.getValue<String>('system_id')!, now, isLocalOrigin, values);
        }
        // Notify streaming queries of the change
        await _streamManager.notifyTableChanged(tableName);
      }

      return result;
    }, tableName: tableName);
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
      final existingRows = await queryMaps(
        (q) {
          q.from(tableName)
              .select(lwwColumns.map((c) => '${c}__hlc').toList().join(', '));
          if (where != null) {
            q.where(RawSqlWhereClause(where, whereArgs));
          }
        },
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
    return await DbExceptionWrapper.wrapDelete(() async {
      // Make sure the table exists or throw an exception
      final _ = _getTableDefinition(tableName);

      final rowsToDelete = await query(
        (q) {
          q.from(tableName).select('system_id, system_is_local_origin');
          if (where != null) {
            q.where(RawSqlWhereClause(where, whereArgs));
          }
        },
      );

      final result = await _db.delete(
        tableName,
        where: where,
        whereArgs: whereArgs,
      );

      if (result > 0) {
        final now = hlcClock.now();
        for (final row in rowsToDelete) {
          final isLocalOrigin = row.getValue<int>('system_is_local_origin') == 1;
          // For deletes, we pass null data since the row is being removed
          await dirtyRowStore?.add(
              tableName, row.getValue<String>('system_id')!, now, isLocalOrigin, null);
        }
        // Notify streaming queries of the change
        await _streamManager.notifyTableChanged(tableName);
      }

      return result;
    }, tableName: tableName);
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
    return await DbExceptionWrapper.wrapRead(() async {
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
    }, tableName: table);
  }

  /// Queries a query and returns a single result, or null if none is found.
  Future<Map<String, Object?>?> queryFirst(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
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
      limit: 1,
      offset: offset,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Queries an entire table and returns typed record objects using registered factories.
  ///
  /// The record type T must be registered with `RecordMapFactoryRegistry.register<T>()`.
  ///
  /// Example:
  /// ```dart
  /// // First register the factory
  /// RecordMapFactoryRegistry.register<User>(User.fromMap);
  ///
  /// // Then query the whole table
  /// final allUsers = await db.queryTableTyped<User>('users');
  /// ```
  Future<List<T>> queryTableTyped<T extends DbRecord>(
    String tableName, {
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
      tableName,
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
    final factory = RecordMapFactoryRegistry.getFactory<T>();
    return results.map((row) => factory(row, this)).toList();
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
  ///   - The `system_is_local_origin` flag is preserved (not overwritten).
  /// - If no local row exists, it's an INSERT marked as server origin.
  ///
  /// Rows processed by this method are NOT marked as dirty, as they represent
  /// data coming from the server rather than local changes to be synchronized.
  ///
  /// ## Constraint Violation Handling
  ///
  /// The [onConstraintViolation] parameter controls how constraint violations
  /// are handled when they occur:
  ///
  /// - `ConstraintViolationStrategy.throwException` (default): Throws the original exception
  /// - `ConstraintViolationStrategy.skip`: Silently skips the problematic row
  ///
  /// The `skip` strategy is useful when loading data from a server where some
  /// rows might conflict with local data, and you want to preserve existing
  /// local data while still loading non-conflicting rows.
  Future<void> bulkLoad(
    String tableName,
    List<Map<String, Object?>> rows, {
    ConstraintViolationStrategy onConstraintViolation = ConstraintViolationStrategy.throwException,
  }) async {
    final tableDef = _getTableDefinition(tableName);
    final pkColumns = tableDef.keys
        .where((k) => k.isPrimary)
        .expand((k) => k.columns)
        .toSet();
    final lwwColumns =
        tableDef.columns.where((c) => c.isLww).map((c) => c.name).toSet();

    for (final row in rows) {
      final systemId = row['system_id'] as String?;
      if (systemId == null) continue;

      final existing = await query(
        (q) => q
            .from(tableName)
            .where(RawSqlWhereClause('system_id = ?', [systemId])).limit(1),
      );

      if (existing.isNotEmpty) {
        // UPDATE logic
        final existingRow = existing.first;
        final valuesToUpdate = <String, Object?>{};
        final now = hlcClock.now();

        for (final entry in row.entries) {
          final colName = entry.key;
          if (pkColumns.contains(colName) || colName.endsWith('__hlc') || colName == 'system_is_local_origin') {
            continue;
          }

          if (lwwColumns.contains(colName)) {
            final hlcColName = '${colName}__hlc';
            final remoteHlcString = row[hlcColName] as String?;

            if (remoteHlcString != null) {
              // If HLC is provided, do a proper LWW comparison.
              final localHlcString =
                  existingRow.getValue<String?>(hlcColName);
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
          try {
            await _update(
              tableName,
              valuesToUpdate,
              now,
              where: 'system_id = ?',
              whereArgs: [systemId],
            );
          } catch (e) {
            if (_isConstraintViolation(e)) {
              await _handleConstraintViolation(
                onConstraintViolation,
                e,
                tableName,
                'UPDATE',
                row,
              );
            } else {
              rethrow;
            }
          }
        }
      } else {
        // INSERT logic - mark as server origin
        try {
          await _insertFromServer(tableName, row, hlcClock.now());
        } catch (e) {
          if (_isConstraintViolation(e)) {
            await _handleConstraintViolation(
              onConstraintViolation,
              e,
              tableName,
              'INSERT',
              row,
            );
          } else {
            rethrow;
          }
        }
      }
    }

    // Notify streaming queries of the change
    await _streamManager.notifyTableChanged(tableName);
  }

  /// Retrieves all dirty rows from the dirty row store.
  ///
  /// This is useful for implementing custom synchronization logic.
  Future<List<DirtyRow>> getDirtyRows() async {
    if (dirtyRowStore == null) {
      return [];
    }
    return await dirtyRowStore!.getAll();
  }

  /// Checks if an exception is a constraint violation
  bool _isConstraintViolation(dynamic exception) {
    final errorMessage = exception.toString().toLowerCase();
    return errorMessage.contains('constraint') ||
           errorMessage.contains('unique') ||
           errorMessage.contains('primary key') ||
           errorMessage.contains('foreign key') ||
           errorMessage.contains('check constraint') ||
           errorMessage.contains('not null constraint') ||
           errorMessage.contains('sqlite_constraint');
  }

  /// Handles constraint violations based on the specified strategy
  Future<void> _handleConstraintViolation(
    ConstraintViolationStrategy strategy,
    dynamic exception,
    String tableName,
    String operation,
    Map<String, Object?> row,
  ) async {
    switch (strategy) {
      case ConstraintViolationStrategy.throwException:
        throw exception;

      case ConstraintViolationStrategy.skip:
        // Log the skip and continue silently
        developer.log(
          '⚠️ Skipping row due to constraint violation in $operation on table $tableName: ${exception.toString()}',
          name: 'BulkLoadConstraintViolation',
          level: 900, // WARNING level
        );
        return;
    }
  }
}

// Static helper methods for settings
Future<String> _setSettingIfNotSet(
  sqflite.DatabaseExecutor db,
  String key,
  String Function() defaultFactory,
) async {
  var result = await _getSetting(db, key);
  result ??= await _setSetting(db, key, defaultFactory());
  return result;
}

Future<String> _setSetting(
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

Future<String?> _getSetting(
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
