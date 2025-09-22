import 'package:declarative_sqlite/src/database.dart';
import 'package:declarative_sqlite/src/record.dart';

/// Factory for creating DbRecord instances from database query results.
class RecordFactory {
  static DbRecord fromMap(
    Map<String, Object?> data,
    String tableName,
    DeclarativeDatabase database, {
    String? updateTable,
  }) {
    return _GenericRecord(data, tableName, database, updateTable: updateTable);
  }

  /// Creates a DbRecord from a table query (CRUD-enabled by default)
  static DbRecord fromTable(
    Map<String, Object?> data,
    String tableName,
    DeclarativeDatabase database,
  ) {
    return _GenericRecord.fromTable(data, tableName, database);
  }

  /// Creates a DbRecord from a view or complex query (read-only by default)
  static DbRecord fromQuery(
    Map<String, Object?> data,
    String tableName,
    DeclarativeDatabase database, {
    String? updateTable,
  }) {
    return _GenericRecord.fromQuery(data, tableName, database, updateTable: updateTable);
  }

  /// Creates a list of records from query results
  static List<DbRecord> fromMapList(
    List<Map<String, Object?>> dataList,
    String tableName,
    DeclarativeDatabase database, {
    String? updateTable,
  }) {
    return dataList
        .map((data) => fromMap(data, tableName, database, updateTable: updateTable))
        .toList();
  }
}

/// Generic implementation of DbRecord for any table
class _GenericRecord extends DbRecord {
  _GenericRecord(
    Map<String, Object?> data,
    String tableName,
    DeclarativeDatabase database, {
    String? updateTable,
  }) : super.fromQuery(data, tableName, database, updateTable: updateTable);

  _GenericRecord.fromTable(
    Map<String, Object?> data,
    String tableName,
    DeclarativeDatabase database,
  ) : super.fromTable(data, tableName, database);

  _GenericRecord.fromQuery(
    Map<String, Object?> data,
    String tableName,
    DeclarativeDatabase database, {
    String? updateTable,
  }) : super.fromQuery(data, tableName, database, updateTable: updateTable);

  /// Provides dynamic property access via noSuchMethod
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    
    // Handle getters (property access)
    if (invocation.isGetter) {
      // Remove 'Symbol("' and '")' from the symbol name
      final propertyName = name.substring(8, name.length - 2);
      
      // Handle special getters
      if (propertyName == 'tableName') return tableName;
      if (propertyName == 'data') return data;
      if (propertyName == 'modifiedFields') return modifiedFields;
      if (propertyName == 'systemId') return systemId;
      if (propertyName == 'systemCreatedAt') return systemCreatedAt;
      if (propertyName == 'systemVersion') return systemVersion;
      if (propertyName == 'isReadOnly') return isReadOnly;
      if (propertyName == 'isCrudEnabled') return isCrudEnabled;
      if (propertyName == 'updateTableName') return updateTableName;
      
      // Handle regular column getters
      return getValue(propertyName);
    }
    
    // Handle setters (property assignment)
    if (invocation.isSetter) {
      // Remove 'Symbol("' and '=")' from the symbol name
      final propertyName = name.substring(8, name.length - 3);
      final value = invocation.positionalArguments.first;
      
      setValue(propertyName, value);
      return;
    }
    
    // Handle method calls
    if (invocation.isMethod) {
      final methodName = name.substring(8, name.length - 2);
      
      switch (methodName) {
        case 'save':
          return save();
        case 'insert':
          return insert();
        case 'delete':
          return delete();
        case 'reload':
          return reload();
        case 'toString':
          return toString();
        default:
          return super.noSuchMethod(invocation);
      }
    }
    
    return super.noSuchMethod(invocation);
  }
}