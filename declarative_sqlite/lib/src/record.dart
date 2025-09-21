import 'package:declarative_sqlite/src/database.dart';
import 'package:declarative_sqlite/src/files/fileset_field.dart';
import 'package:declarative_sqlite/src/schema/column.dart';
import 'package:declarative_sqlite/src/schema/table.dart';
import 'package:declarative_sqlite/src/sync/hlc.dart';

/// Base class for typed database records.
/// 
/// Provides typed getters and setters with automatic conversion between
/// database values and Dart types, including special handling for:
/// - DateTime serialization/deserialization
/// - FilesetField conversion
/// - LWW (Last-Write-Wins) column updates
/// - Automatic dirty tracking for updates
abstract class DbRecord {
  final Map<String, Object?> _data;
  final String _tableName;
  final DeclarativeDatabase _database;
  final Table _tableDefinition;
  
  /// Map to track which fields have been modified since creation
  final Set<String> _modifiedFields = <String>{};
  
  DbRecord(this._data, this._tableName, this._database) 
      : _tableDefinition = _database.schema.userTables.firstWhere(
          (table) => table.name == _tableName,
          orElse: () => throw ArgumentError('Table $_tableName not found in schema'),
        );

  /// Gets the table name for this record
  String get tableName => _tableName;

  /// Gets the underlying data map (read-only copy)
  Map<String, Object?> get data => Map.unmodifiable(_data);

  /// Gets the set of fields that have been modified (read-only copy)
  Set<String> get modifiedFields => Set.unmodifiable(_modifiedFields);

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

  /// Gets a raw value from the data map without type conversion
  Object? getRawValue(String columnName) {
    return _data[columnName];
  }

  /// Gets a typed value with automatic conversion based on column definition
  T? getValue<T>(String columnName) {
    final rawValue = _data[columnName];
    if (rawValue == null) return null;

    final column = _getColumn(columnName);
    
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
  void setValue<T>(String columnName, T? value) {
    final column = _getColumn(columnName);
    Object? databaseValue;
    
    switch (column.logicalType) {
      case 'text':
      case 'guid':
      case 'integer':
      case 'real':
        databaseValue = value;
        break;
      case 'date':
        databaseValue = value != null ? _serializeDateTime(value as DateTime) : null;
        break;
      case 'fileset':
        databaseValue = value != null ? (value as FilesetField).toDatabaseValue() : null;
        break;
      default:
        databaseValue = value;
    }

    _data[columnName] = databaseValue;
    _modifiedFields.add(columnName);

    // Handle LWW column HLC updates
    if (column.isLww) {
      final hlcColumnName = '${columnName}__hlc';
      final currentHlc = _database.hlcClock.now();
      _data[hlcColumnName] = currentHlc.toString();
      _modifiedFields.add(hlcColumnName);
    }
  }

  /// Saves any modified fields back to the database
  Future<void> save() async {
    if (_modifiedFields.isEmpty) return;

    final systemId = this.systemId;
    if (systemId == null) {
      throw StateError('Cannot save record without system_id');
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
        _tableName,
        updateData,
        where: 'system_id = ?',
        whereArgs: [systemId],
      );
    }

    // Clear modified fields after successful save
    _modifiedFields.clear();
  }

  /// Creates a new record in the database with the current data
  Future<void> insert() async {
    // Remove system columns - they'll be added by the database layer
    final insertData = Map<String, Object?>.from(_data);
    insertData.removeWhere((key, value) => key.startsWith('system_'));

    await _database.insert(_tableName, insertData);
    
    // Clear modified fields since this is a new record
    _modifiedFields.clear();
  }

  /// Deletes this record from the database
  Future<void> delete() async {
    final systemId = this.systemId;
    if (systemId == null) {
      throw StateError('Cannot delete record without system_id');
    }

    await _database.delete(
      _tableName,
      where: 'system_id = ?',
      whereArgs: [systemId],
    );
  }

  /// Gets the column definition for the specified column name
  Column _getColumn(String columnName) {
    return _tableDefinition.columns.firstWhere(
      (col) => col.name == columnName,
      orElse: () => throw ArgumentError('Column $columnName not found in table $_tableName'),
    );
  }

  /// Parses a database value into a DateTime
  DateTime _parseDateTime(Object? value) {
    if (value == null) throw ArgumentError('Cannot parse null as DateTime');
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
}