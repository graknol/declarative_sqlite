import 'package:collection/collection.dart';
import 'package:declarative_sqlite/src/declarative_database.dart';
import 'package:declarative_sqlite/src/files/fileset_field.dart';
import 'package:declarative_sqlite/src/schema/db_column.dart';
import 'package:declarative_sqlite/src/schema/db_table.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';

/// Base class for typed database records.
///
/// Provides typed getters and setters with automatic conversion between
/// database values and Dart types, including special handling for:
/// - DateTime serialization/deserialization
/// - FilesetField conversion
/// - LWW (Last-Write-Wins) column updates
/// - Automatic dirty tracking for updates
/// - Read-only vs CRUD differentiation
abstract class DbRecord {
  final Map<String, Object?> _data;
  final String _tableName;
  final DeclarativeDatabase _database;
  final DbTable? _tableDefinition;
  final String? _updateTableName; // Table to target for CRUD operations

  /// Map to track which fields have been modified since creation
  final Set<String> _modifiedFields = <String>{};
  
  /// Tracks whether this is a new record (needs insert) or existing (needs update)
  /// True if record was created without a system_id (new record to be inserted)
  /// False if record was loaded from database (existing record to be updated)
  bool _isNewRecord;

  DbRecord(Map<String, Object?> data, this._tableName, this._database)
    : _data = Map<String, Object?>.from(data), 
    _tableDefinition = _database.schema.userTables.firstWhereOrNull(
        (table) => table.name == _tableName,
      ),
      _updateTableName = _tableName,
      _isNewRecord = data['system_id'] == null;

  /// Gets the table name for this record
  String get tableName => _tableName;

  /// Gets the table name that will be used for CRUD operations
  String? get updateTableName => _updateTableName;

  /// Checks if CRUD operations are allowed on this record's target table
  /// Returns true if the table is in the user tables list (not a view)
  bool get isCrudEnabled {
    final targetTable = _updateTableName ?? _tableName;
    return _database.schema.userTables.any((table) => table.name == targetTable);
  }

  /// Internal method to check CRUD permissions and throw if not allowed
  void _checkCrudPermission(String operation) {
    final targetTable = _updateTableName ?? _tableName;
    final isUserTable = _database.schema.userTables.any((table) => table.name == targetTable);
    
    if (!isUserTable) {
      throw StateError(
        'Cannot $operation record: table "$targetTable" is not a user table (may be a view or system table). Available user tables: ${_database.schema.userTables.map((t) => t.name).join(", ")}'
      );
    }
  }

  /// Gets the underlying data map (read-only copy)
  Map<String, Object?> get data => Map.unmodifiable(_data);

  /// Gets the set of fields that have been modified (read-only copy)
  Set<String> get modifiedFields => Set.unmodifiable(_modifiedFields);
  
  /// Returns true if this record needs to be inserted (new record)
  /// Returns false if this record already exists and needs to be updated
  bool get isNewRecord => _isNewRecord;

  /// Gets the system_id for this record
  String? get systemId => getRawValue('system_id') as String?;

  /// Gets the system_created_at timestamp for this record
  DateTime? get systemCreatedAt {
    final value = getRawValue('system_created_at');
    return value != null ? _parseDateTime(value) : null;
  }

  /// Gets the system_version HLC for this record
  Hlc? get systemVersion {
    final value = getRawValue('system_version');
    return value != null ? Hlc.parse(value as String) : null;
  }

  /// Gets whether this record was created locally (true) or came from server (false)
  /// Returns true if system_is_local_origin is 1 or true, false otherwise (including null)
  bool get isLocalOrigin {
    final value = getRawValue('system_is_local_origin');
    return value == 1 || value == true;
  }

  /// Gets a raw value from the data map without type conversion
  Object? getRawValue(String columnName) {
    return _data[columnName];
  }

  /// Gets a typed value with automatic conversion based on column definition
  T? getValue<T>(String columnName) {
    final rawValue = _data[columnName];
    if (rawValue == null) return null;

    final column = _getColumn(columnName);
    if (column == null) {
      // Fallback for views or complex queries without schema info
      if (T == DateTime) {
        return _parseDateTime(rawValue) as T?;
      }
      if (T == FilesetField) {
        return _parseFilesetField(rawValue) as T?;
      }
      return rawValue as T?;
    }

    switch (column.logicalType) {
      case 'text':
      case 'guid':
        return rawValue as T;
      case 'integer':
        return rawValue as T;
      case 'real':
        return rawValue as T;
      case 'date':
        return _parseDateTime(rawValue) as T;
      case 'fileset':
        return _parseFilesetField(rawValue) as T;
      default:
        return rawValue as T;
    }
  }

  /// Sets a value with automatic conversion and LWW handling  
  /// Throws StateError if the target table doesn't support CRUD operations
  void setValue<T>(String columnName, T? value) {
    _checkCrudPermission('modify');

    // Validate that the column exists in the update table schema
    if (_tableDefinition != null) {
      final column = _getColumn(columnName);
      if (column == null) {
        throw ArgumentError(
          'Column $columnName does not exist in update table $_updateTableName',
        );
      }
      
      // Restrict updates to LWW columns only for rows that came from server
      if (!isLocalOrigin && !column.isLww && !columnName.startsWith('system_')) {
        throw StateError(
          'Column $columnName is not marked as LWW and cannot be updated on rows that originated from server. '
          'Only LWW columns can be updated on existing server rows. '
          'This row is marked as non-local origin (system_is_local_origin = ${getRawValue('system_is_local_origin')})',
        );
      }
    }

    final column = _getColumn(columnName);
    Object? databaseValue;

    switch (column?.logicalType ?? 'unknown') {
      case 'text':
      case 'guid':
      case 'integer':
      case 'real':
        databaseValue = value;
        break;
      case 'date':
        databaseValue = value != null
            ? _serializeDateTime(value as DateTime)
            : null;
        break;
      case 'fileset':
        databaseValue = value != null
            ? (value as FilesetField).toDatabaseValue()
            : null;
        break;
      default:
        databaseValue = value;
    }

    _data[columnName] = databaseValue;
    _modifiedFields.add(columnName);

    // Handle LWW column HLC updates
    if (column?.isLww == true) {
      final hlcColumnName = '${columnName}__hlc';
      final currentHlc = _database.hlcClock.now();
      _data[hlcColumnName] = currentHlc.toString();
      _modifiedFields.add(hlcColumnName);
    }
  }

  // Typed helper methods for generated code

  /// Gets a String value from the specified column.
  /// Returns null if the column value is null.
  String? getText(String columnName) => getValue<String>(columnName);

  /// Gets a non-null String value from the specified column.
  /// Throws if the column value is null.
  String getTextNotNull(String columnName) {
    final value = getText(columnName);
    if (value == null) {
      throw StateError(
        'Column $columnName is null but expected to be non-null',
      );
    }
    return value;
  }

  /// Gets an int value from the specified column.
  /// Returns null if the column value is null.
  int? getInteger(String columnName) => getValue<int>(columnName);

  /// Gets a non-null int value from the specified column.
  /// Throws if the column value is null.
  int getIntegerNotNull(String columnName) {
    final value = getInteger(columnName);
    if (value == null) {
      throw StateError(
        'Column $columnName is null but expected to be non-null',
      );
    }
    return value;
  }

  /// Gets a double value from the specified column.
  /// Returns null if the column value is null.
  double? getReal(String columnName) => getValue<double>(columnName);

  /// Gets a non-null double value from the specified column.
  /// Throws if the column value is null.
  double getRealNotNull(String columnName) {
    final value = getReal(columnName);
    if (value == null) {
      throw StateError(
        'Column $columnName is null but expected to be non-null',
      );
    }
    return value;
  }

  /// Gets a DateTime value from the specified column.
  /// Returns null if the column value is null.
  DateTime? getDateTime(String columnName) => getValue<DateTime>(columnName);

  /// Gets a non-null DateTime value from the specified column.
  /// Throws if the column value is null.
  DateTime getDateTimeNotNull(String columnName) {
    final value = getDateTime(columnName);
    if (value == null) {
      throw StateError(
        'Column $columnName is null but expected to be non-null',
      );
    }
    return value;
  }

  /// Gets a FilesetField value from the specified column.
  /// Returns null if the column value is null.
  FilesetField? getFilesetField(String columnName) =>
      getValue<FilesetField>(columnName);

  /// Gets a non-null FilesetField value from the specified column.
  /// Throws if the column value is null.
  FilesetField getFilesetFieldNotNull(String columnName) {
    final value = getFilesetField(columnName);
    if (value == null) {
      throw StateError(
        'Column $columnName is null but expected to be non-null',
      );
    }
    return value;
  }

  // Typed setter methods for generated code

  /// Sets a String value for the specified column.
  void setText(String columnName, String? value) => setValue(columnName, value);

  /// Sets an int value for the specified column.
  void setInteger(String columnName, int? value) => setValue(columnName, value);

  /// Sets a double value for the specified column.
  void setReal(String columnName, double? value) => setValue(columnName, value);

  /// Sets a DateTime value for the specified column.
  void setDateTime(String columnName, DateTime? value) =>
      setValue(columnName, value);

  /// Sets a FilesetField value for the specified column.
  void setFilesetField(String columnName, FilesetField? value) =>
      setValue(columnName, value);

  /// Saves the record to the database.
  /// 
  /// Automatically determines whether to insert (for new records) or update (for existing records).
  /// - For new records (created without system_id): performs an INSERT
  /// - For existing records (loaded from database): performs an UPDATE of modified fields only
  /// 
  /// Throws StateError if the target table doesn't support CRUD operations
  Future<void> save() async {
    _checkCrudPermission('save');

    if (_isNewRecord) {
      // New record - perform insert
      await _performInsert();
    } else {
      // Existing record - perform update of modified fields
      await _performUpdate();
    }
  }
  
  /// Internal method to perform the actual update operation
  Future<void> _performUpdate() async {
    if (_modifiedFields.isEmpty) return;

    final systemId = this.systemId;
    if (systemId == null) {
      throw StateError('Cannot update record without system_id');
    }

    final systemVersion = this.systemVersion;
    if (systemVersion == null) {
      throw StateError('Cannot update record without system_version');
    }

    // Build update map with only modified fields (excluding system columns)
    final updateData = <String, Object?>{};
    for (final fieldName in _modifiedFields) {
      // Skip system columns - they're managed by the database layer
      if (!fieldName.startsWith('system_')) {
        updateData[fieldName] = _data[fieldName];
      }
    }

    if (updateData.isNotEmpty) {
      await _database.update(
        _updateTableName ?? _tableName,
        updateData,
        where: 'system_id = ?',
        whereArgs: [systemId],
      );
    }

    // Clear modified fields after successful save
    _modifiedFields.clear();
  }
  
  /// Internal method to perform the actual insert operation
  Future<void> _performInsert() async {
    // Remove system columns - they'll be added by the database layer
    final insertData = Map<String, Object?>.from(_data);
    insertData.removeWhere((key, value) => key.startsWith('system_'));

    final systemId = await _database.insert(_updateTableName ?? _tableName, insertData);
    
    // Reload the record from database to get all system columns
    final results = await _database.queryTable(
      _updateTableName ?? _tableName,
      where: 'system_id = ?',
      whereArgs: [systemId],
    );
    
    if (results.isEmpty) {
      throw StateError('Failed to reload record after insert');
    }
    
    // Update the record's data with fresh data from database
    _data.clear();
    _data.addAll(results.first);
    _isNewRecord = false;

    // Clear modified fields since this is now persisted
    _modifiedFields.clear();
  }

  /// Creates a new record in the database with the current data
  /// 
  /// Note: Consider using `save()` instead, which automatically handles both insert and update.
  /// 
  /// Throws StateError if the target table doesn't support CRUD operations
  @Deprecated('Use save() instead, which automatically handles insert vs update')
  Future<void> insert() async {
    _checkCrudPermission('insert');

    // Remove system columns - they'll be added by the database layer
    final insertData = Map<String, Object?>.from(_data);
    insertData.removeWhere((key, value) => key.startsWith('system_'));

    final systemId = await _database.insert(_updateTableName ?? _tableName, insertData);
    
    // Update the record's data with the new system_id and mark as no longer new
    _data['system_id'] = systemId;
    _isNewRecord = false;

    // Clear modified fields since this is now persisted
    _modifiedFields.clear();
  }

  /// Deletes this record from the database
  /// Throws StateError if the target table doesn't support CRUD operations
  Future<void> delete() async {
    _checkCrudPermission('delete');

    final systemId = this.systemId;
    if (systemId == null) {
      throw StateError('Cannot delete record without system_id');
    }

    await _database.delete(
      _updateTableName ?? _tableName,
      where: 'system_id = ?',
      whereArgs: [systemId],
    );
  }

  /// Reloads this record from the database
  /// Only available for CRUD-enabled records as views cannot guarantee uniqueness
  Future<void> reload() async {
    _checkCrudPermission('reload');

    final systemId = this.systemId;
    if (systemId == null) {
      throw StateError('Cannot reload record without system_id');
    }

    final results = await _database.queryTable(
      _updateTableName ?? _tableName,
      where: 'system_id = ?',
      whereArgs: [systemId],
    );

    if (results.isEmpty) {
      throw StateError(
        'Record with system_id $systemId not found in table ${_updateTableName ?? _tableName}',
      );
    }

    // Update the data map with fresh data
    _data.clear();
    _data.addAll(results.first);
    
    // Mark as existing record since we just loaded from database
    _isNewRecord = false;

    // Clear modified fields since we have fresh data
    _modifiedFields.clear();
  }

  /// Gets the column definition for the specified column name
  DbColumn? _getColumn(String columnName) {
    return _tableDefinition?.columns.firstWhereOrNull(
      (col) => col.name == columnName,
    );
  }

  /// Parses a database value into a DateTime
  DateTime _parseDateTime(Object? value) {
    if (value == null || value == "") throw ArgumentError('Cannot parse null as DateTime');
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    throw ArgumentError('Cannot parse $value as DateTime');
  }

  /// Serializes a DateTime for database storage
  String _serializeDateTime(DateTime dateTime) {
    return dateTime.toIso8601String();
  }

  /// Parses a database value into a FilesetField
  FilesetField? _parseFilesetField(Object? value) {
    if (value == null) return null;
    return FilesetField.fromDatabaseValue(value, _database);
  }

  @override
  String toString() {
    return '$runtimeType($_tableName: $_data)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DbRecord &&
        other._tableName == _tableName &&
        other._data.toString() == _data.toString();
  }

  @override
  int get hashCode => _tableName.hashCode ^ _data.toString().hashCode;

  Object? operator [](String key) {
    return data[key];
  }
}
