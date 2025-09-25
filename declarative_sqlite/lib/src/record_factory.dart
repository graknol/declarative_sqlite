import 'package:declarative_sqlite/src/declarative_database.dart';
import 'package:declarative_sqlite/src/db_record.dart';

/// Factory for creating DbRecord instances from database query results.
class RecordFactory {
  static DbRecord fromMap(
    Map<String, Object?> data,
    String tableName,
    DeclarativeDatabase database,
  ) {
    return _GenericRecord(data, tableName, database);
  }

  /// Creates a list of records from query results
  static List<DbRecord> fromMapList(
    List<Map<String, Object?>> dataList,
    String tableName,
    DeclarativeDatabase database,
  ) {
    return dataList
        .map((data) => fromMap(data, tableName, database))
        .toList();
  }
}

/// Generic implementation of DbRecord for any table
class _GenericRecord extends DbRecord {
  _GenericRecord(super.data, super.tableName, super.database);

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
