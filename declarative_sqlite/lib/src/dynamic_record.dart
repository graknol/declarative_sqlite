import 'package:meta/meta.dart';
import 'data_access.dart';

/// A wrapper around Map<String, dynamic> that provides ergonomic property-based access to column data.
/// 
/// This class uses `noSuchMethod` to allow accessing column values as properties and calling setters
/// that update the database:
/// ```dart
/// final row = DynamicRecord({'name': 'Alice', 'age': 30});
/// print(row.name);  // 'Alice' - equivalent to row['name']
/// print(row.age);   // 30 - equivalent to row['age']
/// 
/// // Support for interface-like access:
/// interface IUser {
///   int get id;
///   String get name;
///   Future<void> setName(String value);
/// }
/// 
/// final users = await query.executeMany<IUser>(dataAccess);
/// final user = users.first as IUser;
/// print(user.id);   // Access via interface getter
/// await user.setName('Bob');  // Update via interface setter
/// ```
class DynamicRecord {
  /// The underlying data map
  final Map<String, dynamic> data;
  
  /// DataAccess instance for setter operations (optional)
  final DataAccess? _dataAccess;
  
  /// Table name for setter operations (optional)
  final String? _tableName;
  
  /// Primary key column name for updates (optional)
  final String? _primaryKeyColumn;

  /// Creates a new DynamicRecord with the given data
  const DynamicRecord(this.data, {
    DataAccess? dataAccess,
    String? tableName,
    String? primaryKeyColumn,
  }) : _dataAccess = dataAccess,
       _tableName = tableName,
       _primaryKeyColumn = primaryKeyColumn;

  /// Get column value using index operator (existing functionality)
  dynamic operator [](String columnName) => data[columnName];

  /// Check if a column exists
  bool containsKey(String columnName) => data.containsKey(columnName);

  /// Get all column names
  Set<String> get columnNames => data.keys.toSet();

  /// Convert to regular Map for compatibility
  Map<String, dynamic> toMap() => Map<String, dynamic>.from(data);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      // Get the column name from the symbol
      String columnName = invocation.memberName.toString();
      // Remove the Symbol("") wrapper
      if (columnName.startsWith('Symbol("') && columnName.endsWith('")')) {
        columnName = columnName.substring(8, columnName.length - 2);
      }
      
      // Direct property access: row.columnName
      if (data.containsKey(columnName)) {
        return data[columnName];
      }
      
      // Typed getters for type safety and conversion
      if (columnName.startsWith('getString') && columnName.length > 9) {
        final realColumn = _extractColumnName(columnName, 'getString');
        return data[realColumn] as String?;
      }
      
      if (columnName.startsWith('getInt') && columnName.length > 6) {
        final realColumn = _extractColumnName(columnName, 'getInt');
        final value = data[realColumn];
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value);
        return value as int?;
      }
      
      if (columnName.startsWith('getDouble') && columnName.length > 9) {
        final realColumn = _extractColumnName(columnName, 'getDouble');
        final value = data[realColumn];
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value);
        return value as double?;
      }
      
      if (columnName.startsWith('getBool') && columnName.length > 7) {
        final realColumn = _extractColumnName(columnName, 'getBool');
        final value = data[realColumn];
        if (value is bool) return value;
        if (value is int) return value != 0;
        if (value is String) return value.toLowerCase() == 'true';
        return value as bool?;
      }
      
      if (columnName.startsWith('getDate') && columnName.length > 7) {
        final realColumn = _extractColumnName(columnName, 'getDate');
        final value = data[realColumn];
        if (value is DateTime) return value;
        if (value is String) return DateTime.tryParse(value);
        if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
        return value as DateTime?;
      }
      
      // Allow access to snake_case columns via camelCase properties
      final snakeCase = _camelToSnakeCase(columnName);
      if (data.containsKey(snakeCase)) {
        return data[snakeCase];
      }
    } else if (invocation.isMethod) {
      // Handle setter method calls like setColumnName(value)
      String methodName = invocation.memberName.toString();
      if (methodName.startsWith('Symbol("') && methodName.endsWith('")')) {
        methodName = methodName.substring(8, methodName.length - 2);
      }
      
      if (methodName.startsWith('set') && methodName.length > 3) {
        final columnName = _extractColumnName(methodName, 'set');
        final value = invocation.positionalArguments.isNotEmpty 
            ? invocation.positionalArguments.first 
            : null;
        
        return _updateColumn(columnName, value);
      }
    }
    
    return super.noSuchMethod(invocation);
  }

  /// Updates a column value in the database
  Future<void> _updateColumn(String columnName, dynamic value) async {
    if (_dataAccess == null || _tableName == null || _primaryKeyColumn == null) {
      throw StateError(
        'Cannot update column: DynamicRecord must be created with dataAccess, tableName, and primaryKeyColumn'
      );
    }
    
    final primaryKeyValue = data[_primaryKeyColumn];
    if (primaryKeyValue == null) {
      throw StateError('Cannot update: primary key value is null');
    }
    
    // Update the database
    await _dataAccess!.updateByPrimaryKey(_tableName!, primaryKeyValue, {columnName: value});
    
    // Update local data to reflect the change
    data[columnName] = value;
  }

  /// Extract column name from typed getter/setter, converting from PascalCase to snake_case
  String _extractColumnName(String methodName, String prefix) {
    final columnPascal = methodName.substring(prefix.length);
    return _camelToSnakeCase(columnPascal);
  }

  /// Convert camelCase or PascalCase to snake_case
  String _camelToSnakeCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    ).replaceFirst(RegExp(r'^_'), '');
  }

  @override
  String toString() => 'DynamicRecord($data)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DynamicRecord && 
           other.data.toString() == data.toString();
  }

  @override
  int get hashCode => data.hashCode;
}